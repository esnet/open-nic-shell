module system_config_vpd #(
    parameter              PRODUCT_ID      = "ESnet SmartNIC",
    parameter logic [31:0] CMS_REG_OFFSET  = 0,
    parameter logic [31:0] QSPI_REG_OFFSET = 0,
    parameter logic [31:0] BUILD_ID        = 0
) (
    input  logic        clk,
    input  logic        srst,

    output logic        init_done,
    output logic        init_error,

    // VPD interface (one per physical function)
    input  logic        vpd_req,
    input  logic        vpd_wr_rd_n,
    input  logic [14:0] vpd_addr,
    input  logic [7:0]  vpd_wr_data,
    output logic [7:0]  vpd_rd_data,
    output logic        vpd_rd_vld,

    // Card info interface (from CMS)
    input  logic        card_info_vld,
    input  logic [7:0]  card_info_len,
    output logic        card_info_rd,
    output logic [7:0]  card_info_rd_addr,
    input  logic [7:0]  card_info_rd_data,
    input  logic        card_info_rd_vld
);
    // Parameters
    localparam logic [7:0]  CARD_INFO_KEY__CARD_SN    = 8'h21;
    localparam logic [7:0]  CARD_INFO_KEY__CARD_NAME  = 8'h27;
    localparam logic [7:0]  CARD_INFO_KEY__SC_VERSION = 8'h28;

    localparam int          CARD_INFO_MAX_LEN = 128;
    localparam int          CARD_INFO_IDX_WID = $clog2(CARD_INFO_MAX_LEN);
    localparam int          CARD_INFO_SIZE_WID = $clog2(CARD_INFO_MAX_LEN+1);

    localparam int          VPD_MAX_LEN = 256;
    localparam int          VPD_IDX_WID = $clog2(VPD_MAX_LEN);
    localparam int          VPD_SIZE_WID = $clog2(VPD_MAX_LEN+1);

    localparam logic [15:0] PRODUCT_ID_LEN = $bits(PRODUCT_ID)/8 + 1; // Account for null string termination

    localparam int VPD_RO_START_OFFSET = 3 + PRODUCT_ID_LEN;
    localparam logic [15:0] VPD_RO_LEN = (VPD_MAX_LEN-1) - VPD_RO_START_OFFSET - 3; // Size of VPD-R (read-only data)
    localparam int VPD_V0_START_OFFSET = VPD_RO_START_OFFSET + 3;
    localparam int VPD_V1_START_OFFSET = VPD_V0_START_OFFSET + 7;
    localparam int VPD_V2_START_OFFSET = VPD_V1_START_OFFSET + 7;
    localparam int VPD_CARDINFO_START_OFFSET = VPD_V2_START_OFFSET + 7;
    localparam int VPD_VAR_START_OFFSET = VPD_CARDINFO_START_OFFSET; // Start of 'variable' data, retrieved from card info
                                                                     // ... or, end of 'static' data

    localparam int VPD_ROM_SIZE = VPD_VAR_START_OFFSET;
    localparam int VPD_ROM_SIZE_WID = $clog2(VPD_ROM_SIZE);
    localparam int VPD_VAR_SIZE = VPD_MAX_LEN-VPD_VAR_START_OFFSET;
    localparam int VPD_VAR_SIZE_WID = $clog2(VPD_VAR_SIZE);

    // Typedefs
    typedef enum logic {
        VPD_RESOURCE_TYPE__SMALL = 0,
        VPD_RESOURCE_TYPE__LARGE = 1
    } vpd_resource_type_t;

    typedef enum logic [6:0] {
        VPD_TAG_INVALID = 7'h0,
        VPD_TAG_ID      = 7'h2,
        VPD_TAG_END     = 7'hf,
        VPD_TAG_VPD_R   = 7'h10,
        VPD_TAG_VPD_W   = 7'h11
    } vpd_tag_t;

    typedef logic [3:0] vpd_tag_small_t;

    typedef struct packed {
        vpd_resource_type_t _type; // 0 for small resource data type
        vpd_tag_small_t     tag;
        logic [2:0]         len;
    } vpd_srdt_t;

    typedef struct packed {
        vpd_resource_type_t _type; // 1 for small resource data type
        vpd_tag_t           tag;
    } vpd_lrdt_t;

    typedef enum logic [3:0] {
        RESET,
        IDLE,
        GET_CARD_NAME,
        CARD_NAME_WRITE_TO_VPD,
        GET_CARD_SN,
        CARD_SN_WRITE_TO_VPD,
        GET_SC_VERSION,
        SC_VERSION_WRITE_TO_VPD,
        CHKSUM,
        DONE,
        ERROR
    } state_t;

    typedef enum logic [3:0] {
        PARSE_RESET,
        PARSE_IDLE,
        PARSE_INIT,
        PARSE_GET_KEY,
        PARSE_WAIT_KEY,
        PARSE_GET_LEN,
        PARSE_WAIT_LEN,
        PARSE_TEST_LEN,
        PARSE_EVAL,
        PARSE_SKIP_VALUE,
        PARSE_DONE,
        PARSE_ERROR,
        PARSE_KEY_NOT_FOUND
    } parse_state_t;

    typedef enum logic [3:0] {
        VPD_RESET,
        VPD_IDLE,
        VPD_WR,
        VPD_WR_TAG,
        VPD_WR_LEN,
        VPD_RD_CARDINFO,
        VPD_WAIT_CARDINFO,
        VPD_WR_DATA,
        VPD_CHKSUM_WR_TAG,
        VPD_CHKSUM_WR_LEN,
        VPD_CHKSUM_INIT,
        VPD_CHKSUM_RD_DATA,
        VPD_CHKSUM_ACC,
        VPD_CHKSUM_WR_DATA,
        VPD_DONE,
        VPD_ERROR
    } vpd_state_t;

    // Functions
    function vpd_tag_small_t vpd_get_small_tag(input vpd_tag_t tag);
        if (tag <= 'hf) return vpd_tag_small_t'(tag);
        else            return vpd_tag_small_t'(VPD_TAG_INVALID);
    endfunction

    function logic [7:0] vpd_get_srdt(input vpd_tag_t tag, input logic [2:0] len);
        vpd_srdt_t srdt;
        srdt._type = VPD_RESOURCE_TYPE__SMALL;
        srdt.tag = vpd_get_small_tag(tag);
        srdt.len = len;
        return srdt;
    endfunction

    function logic [7:0] vpd_get_lrdt(input vpd_tag_t tag);
        vpd_lrdt_t lrdt;
        lrdt._type = VPD_RESOURCE_TYPE__LARGE;
        lrdt.tag = tag;
        return lrdt;
    endfunction

    localparam logic [7:0] VPD_LRDT_ID    = vpd_get_lrdt(VPD_TAG_ID);
    localparam logic [7:0] VPD_LRDT_VPD_R = vpd_get_lrdt(VPD_TAG_VPD_R);
    localparam logic [7:0] VPD_SRDT_END   = vpd_get_srdt(VPD_TAG_END, 0);

    // Signals
    state_t                       state;
    state_t                       nxt_state;

    logic                         __init_done;
    logic                         __init_error;

    parse_state_t                 parse_state;
    parse_state_t                 nxt_parse_state;

    logic                         reset_parse_idx;
    logic [CARD_INFO_IDX_WID-1:0] parse_idx_incr;
    logic [CARD_INFO_IDX_WID-1:0] parse_idx;
    logic                         parse_req;
    logic [7:0]                   parse_key;
    logic [CARD_INFO_IDX_WID-1:0] parse_len;
    logic                         latch_key;
    logic                         latch_len;
    logic [7:0]                   found_key;

    logic                         parse_cardinfo_rd;

    vpd_state_t                   vpd_state;
    vpd_state_t                   nxt_vpd_state;

    logic                         reset_vpd_init_idx;
    logic                         inc_vpd_init_idx;
    logic [VPD_VAR_SIZE_WID-1:0]  vpd_init_idx;

    logic                         vpd_chksum_init;
    logic [VPD_VAR_SIZE_WID-1:0]  vpd_chksum_idx;
    logic [7:0]                   vpd_sum;
    logic [7:0]                   vpd_chksum;
    logic                         vpd_wr_req;
    logic [0:1][7:0]              vpd_wr_tag;
    logic                         vpd_chksum_req;
    logic                         vpd_cardinfo_rd;
    logic [CARD_INFO_IDX_WID-1:0] vpd_cardinfo_rd_addr;
    logic                         vpd_cardinfo_rd_vld;

    logic                         vpd_init_wr;
    logic [7:0]                   vpd_init_wr_data;
    logic                         vpd_init_rd;
    logic [7:0]                   vpd_init_rd_data;

    logic                         reset_vpd_byte_idx;
    logic [CARD_INFO_IDX_WID-1:0] vpd_byte_idx;
    logic                         vpd_chksum_acc;

    logic [7:0]                   vpd_rom_rd_data;

    logic                         vpd_ram_req;
    logic                         vpd_ram_wr_rd_n;
    logic [14:0]                  vpd_ram_addr;
    logic [7:0]                   vpd_ram_wr_data;
    logic [7:0]                   vpd_ram_rd_data;

    logic [14:0]                  vpd_addr_r;

    // VPD data structure
    logic [0:VPD_ROM_SIZE-1][7:0] VPD_ROM;
    logic [7:0] VPD_RAM [VPD_VAR_SIZE];
    

    localparam logic [0:VPD_ROM_SIZE-1][7:0] VPD_ROM_CONTENTS = {
    // -- Product ID Section
        VPD_LRDT_ID,
        PRODUCT_ID_LEN[7:0], PRODUCT_ID_LEN[15:8],
        PRODUCT_ID, 8'h0,
    // -- VPD-R (read-only) Section
        VPD_LRDT_VPD_R,
        // VPD-R section extends from here until the end of the
        // (fixed-size) data structure; this is possible by filling
        // 'zero' bytes in the RV field)
        VPD_RO_LEN[7:0], VPD_RO_LEN[15:8],
        "V0", 8'h04, BUILD_ID,
        "V1", 8'h04, QSPI_REG_OFFSET,
        "V2", 8'h04, CMS_REG_OFFSET
    // -- Variable data (i.e. card info) goes here (populated by Init FSM)
    };

    function automatic logic [7:0] get_rom_byte_sum();
        automatic logic [7:0] sum = 0;
        for (int i = 0; i < VPD_ROM_SIZE; i++) sum += VPD_ROM_CONTENTS[i];
        return sum;
    endfunction

    localparam logic [7:0] VPD_ROM_CHECKSUM = get_rom_byte_sum();

    // ROM containing 'static' elements; card info is filled in
    // by the state machine after retrieval from CMS/SC
    initial VPD_ROM = VPD_ROM_CONTENTS;

    always_ff @(posedge clk) vpd_rom_rd_data <= VPD_ROM[vpd_addr[VPD_ROM_SIZE_WID-1:0]];

    // Init (main) FSM
    // - Manage population of (non-static) elements of the VPD data structure
    // - The main content for this is cardinfo data, retrieved at initialization
    //   from System Controller (via CMS)
    initial state = RESET;
    always @(posedge clk) begin
        if (srst) state <= RESET;
        else      state <= nxt_state;
    end

    always_comb begin
        nxt_state = state;
        reset_vpd_init_idx = 1'b0;
        parse_req = 1'b0;
        parse_key = 'h0;
        vpd_wr_req = 1'b0;
        vpd_wr_tag = '0;
        vpd_chksum_req = 1'b0;
        __init_done = 1'b0;
        __init_error = 1'b0;
        case (state)
            RESET : begin
                if (card_info_vld) nxt_state = IDLE;
            end
            IDLE : begin
                reset_vpd_init_idx = 1'b1;
                nxt_state = GET_CARD_NAME;
            end
            GET_CARD_NAME : begin
                parse_req = 1'b1;
                parse_key = CARD_INFO_KEY__CARD_NAME;
                if (parse_state == PARSE_DONE)       nxt_state = CARD_NAME_WRITE_TO_VPD;
                else if (parse_state == PARSE_ERROR) nxt_state = GET_CARD_SN;
            end
            CARD_NAME_WRITE_TO_VPD: begin
                vpd_wr_req = 1'b1;
                vpd_wr_tag = "PN";
                if (vpd_state == VPD_DONE)       nxt_state = GET_CARD_SN;
                else if (vpd_state == VPD_ERROR) nxt_state = ERROR;
            end
            GET_CARD_SN : begin
                parse_req = 1'b1;
                parse_key = CARD_INFO_KEY__CARD_SN;
                if (parse_state == PARSE_DONE)       nxt_state = CARD_SN_WRITE_TO_VPD;
                else if (parse_state == PARSE_ERROR) nxt_state = GET_SC_VERSION;
            end
            CARD_SN_WRITE_TO_VPD: begin
                vpd_wr_req = 1'b1;
                vpd_wr_tag = "SN";
                if (vpd_state == VPD_DONE)       nxt_state = GET_SC_VERSION;
                else if (vpd_state == VPD_ERROR) nxt_state = ERROR;
            end
            GET_SC_VERSION : begin
                parse_req = 1'b1;
                parse_key = CARD_INFO_KEY__SC_VERSION;
                if (parse_state == PARSE_DONE)       nxt_state = SC_VERSION_WRITE_TO_VPD;
                else if (parse_state == PARSE_ERROR) nxt_state = CHKSUM;
            end 
            SC_VERSION_WRITE_TO_VPD : begin
                vpd_wr_req = 1'b1;
                vpd_wr_tag = "V3";
                if (vpd_state == VPD_DONE)       nxt_state = CHKSUM;
                else if (vpd_state == VPD_ERROR) nxt_state = ERROR;
            end
            CHKSUM : begin
                vpd_chksum_req = 1'b1;
                vpd_wr_tag = "RV";
                if (vpd_state == VPD_DONE)       nxt_state = DONE;
                else if (vpd_state == VPD_ERROR) nxt_state = ERROR;
            end
            DONE : begin
                __init_done = 1'b1;
            end
            ERROR : begin
                __init_error = 1'b1;
            end
        endcase
    end

    // Manage pointer into VPD data structure
    // - this pointer is used to populate cardinfo on init
    // - start at the specified start offset (immediately following any 'static' records)
    // - increment as new data is written into the VPD structure
    always @(posedge clk) begin
        if (reset_vpd_init_idx)    vpd_init_idx <= 0;
        else if (vpd_chksum_init)  vpd_init_idx <= 0;
        else if (inc_vpd_init_idx) vpd_init_idx <= vpd_init_idx + 1;
    end

    // VPD FSM
    // - manages init accesses to VPD data structure, including:
    //   - writing card info data elements as VPD TLVs
    //   - calculating and populating VPD-R checksum
    //   - writing end tag
    initial vpd_state = VPD_RESET;
    always @(posedge clk) begin
        if (srst) vpd_state <= VPD_RESET;
        else      vpd_state <= nxt_vpd_state;
    end

    always_comb begin
        nxt_vpd_state = vpd_state;
        reset_vpd_byte_idx = 1'b0;
        inc_vpd_init_idx = 1'b0;
        vpd_init_wr = 1'b0;
        vpd_init_rd = 1'b0;
        vpd_cardinfo_rd = 1'b0;
        vpd_chksum_init = 1'b0;
        vpd_chksum_acc = 1'b0;
        case (vpd_state)
            VPD_RESET : begin
                nxt_vpd_state = VPD_IDLE;
            end
            VPD_IDLE : begin
                reset_vpd_byte_idx = 1'b1;
                if (vpd_wr_req)          nxt_vpd_state = VPD_WR;
                else if (vpd_chksum_req) nxt_vpd_state = VPD_CHKSUM_WR_TAG;
            end
            VPD_WR : begin
                if (vpd_init_idx + parse_len + 3 < VPD_MAX_LEN-1) nxt_vpd_state = VPD_WR_TAG;
                else                                              nxt_vpd_state = VPD_ERROR;
            end
            VPD_WR_TAG : begin
                vpd_init_wr = 1'b1;
                inc_vpd_init_idx = 1'b1;
                if (vpd_byte_idx == 1) nxt_vpd_state = VPD_WR_LEN;
            end
            VPD_WR_LEN : begin
                vpd_init_wr = 1'b1;
                inc_vpd_init_idx = 1'b1;
                nxt_vpd_state = VPD_RD_CARDINFO;
            end
            VPD_RD_CARDINFO: begin
                vpd_cardinfo_rd = 1'b1;
                nxt_vpd_state = VPD_WAIT_CARDINFO;
            end
            VPD_WAIT_CARDINFO: begin
                if (card_info_rd_vld) nxt_vpd_state = VPD_WR_DATA;
            end
            VPD_WR_DATA : begin
                vpd_init_wr = 1'b1;
                inc_vpd_init_idx = 1'b1;
                if (vpd_byte_idx == 3+parse_len-1) nxt_vpd_state = VPD_DONE;
                else                               nxt_vpd_state = VPD_RD_CARDINFO;
            end
            VPD_CHKSUM_WR_TAG : begin
                vpd_init_wr = 1'b1;
                inc_vpd_init_idx = 1'b1;
                if (vpd_byte_idx == 1) nxt_vpd_state = VPD_CHKSUM_WR_LEN;
            end
            VPD_CHKSUM_WR_LEN : begin
                vpd_init_wr = 1'b1;
                inc_vpd_init_idx = 1'b1;
                nxt_vpd_state = VPD_CHKSUM_INIT;
            end
            VPD_CHKSUM_INIT : begin
                vpd_chksum_init = 1'b1;
                if (vpd_init_idx + 4 < VPD_MAX_LEN-1) nxt_vpd_state = VPD_CHKSUM_RD_DATA;
                else                                  nxt_vpd_state = VPD_ERROR;
            end
            VPD_CHKSUM_RD_DATA : begin
                vpd_init_rd = 1'b1;
                inc_vpd_init_idx = 1'b1;
                nxt_vpd_state = VPD_CHKSUM_ACC;
            end
            VPD_CHKSUM_ACC : begin
                vpd_chksum_acc = 1'b1;
                if (vpd_init_idx == vpd_chksum_idx) nxt_vpd_state = VPD_CHKSUM_WR_DATA;
                else                                nxt_vpd_state = VPD_CHKSUM_RD_DATA;
            end
            VPD_CHKSUM_WR_DATA : begin
                vpd_init_wr = 1'b1;
                inc_vpd_init_idx = 1'b1;
                nxt_vpd_state = VPD_DONE;
            end
            VPD_DONE : begin
                nxt_vpd_state = VPD_IDLE;
            end
            VPD_ERROR : begin
                nxt_vpd_state = VPD_IDLE;
            end
        endcase
    end

    // Manage current element byte pointer
    always_ff @(posedge clk) begin
        if (reset_vpd_byte_idx)    vpd_byte_idx <= 0;
        else if (inc_vpd_init_idx) vpd_byte_idx <= vpd_byte_idx + 1;
    end

    // Cardinfo data mux
    assign card_info_rd      = (parse_state == PARSE_IDLE) ? vpd_cardinfo_rd      : parse_cardinfo_rd;
    assign card_info_rd_addr = (parse_state == PARSE_IDLE) ? vpd_cardinfo_rd_addr : parse_idx;

    // Adjust card info pointer to account for type and length fields
    assign vpd_cardinfo_rd_addr = parse_idx + vpd_byte_idx - 3;

    // Write data mux
    always_comb begin
        case (vpd_state)
            VPD_WR_TAG, VPD_CHKSUM_WR_TAG : vpd_init_wr_data = vpd_wr_tag[vpd_byte_idx];
            VPD_WR_LEN                    : vpd_init_wr_data = parse_len;
            VPD_WR_DATA                   : vpd_init_wr_data = card_info_rd_data;
            VPD_CHKSUM_WR_LEN             : vpd_init_wr_data = (VPD_MAX_LEN-VPD_ROM_SIZE-1) - vpd_init_idx - 1; // Zero-pad to end of VPD (except for END tag)
            VPD_CHKSUM_WR_DATA            : vpd_init_wr_data = vpd_chksum;
            default                       : vpd_init_wr_data = '0;
        endcase
    end

    // Latch checksum byte offset
    // - checksum is the value that needs to be added to the sum of all
    //   bytes, from byte 0 to this offset, to make the sum 0
    //  -when calculated, the checksum is written to this location
    always_ff @(posedge clk) if (vpd_chksum_init) vpd_chksum_idx <= vpd_init_idx;

    // Calulate sum of all RO bytes
    always_ff @(posedge clk) begin
        if (vpd_chksum_init) vpd_sum <= VPD_ROM_CHECKSUM;
        else if (vpd_chksum_acc) vpd_sum <= vpd_sum + vpd_init_rd_data;
    end

    // Determine checksum
    assign vpd_chksum = 9'h100 - vpd_sum;

    // Card info parse FSM
    // - Given a key (parse_key), find the length of the associated
    //   data value (parse_len) and the offset of the data value
    //   within the cardinfo data structure (parse_idx)
    // - If matching key is found, traverse PARSE_DONE state
    // - If parsing error occurs (e.g. attempt to read past end of array)
    //   or key is not found, traverse PARSE_ERROR state
    initial parse_state = PARSE_RESET;
    always @(posedge clk) begin
        if (srst) parse_state <= PARSE_RESET;
        else      parse_state <= nxt_parse_state;
    end

    always_comb begin
        nxt_parse_state = parse_state;
        reset_parse_idx = 1'b0;
        parse_idx_incr = '0;
        parse_cardinfo_rd = 1'b0;
        latch_key = 1'b0;
        latch_len = 1'b0;
        case (parse_state)
            PARSE_RESET : begin
                nxt_parse_state = PARSE_IDLE;
            end
            PARSE_IDLE : begin
                if (parse_req) nxt_parse_state = PARSE_INIT;
            end
            PARSE_INIT : begin
                reset_parse_idx = 1'b1;
                nxt_parse_state = PARSE_GET_KEY;
            end
            PARSE_GET_KEY : begin
                parse_cardinfo_rd = 1'b1;
                parse_idx_incr = 1;
                nxt_parse_state = PARSE_WAIT_KEY;
            end
            PARSE_WAIT_KEY : begin
                latch_key = 1'b1;
                if (card_info_rd_vld) begin
                    if (parse_idx < card_info_len) nxt_parse_state = PARSE_GET_LEN;
                    else                           nxt_parse_state = PARSE_ERROR;
                end
            end
            PARSE_GET_LEN : begin
                parse_cardinfo_rd = 1'b1;
                parse_idx_incr = 1;
                nxt_parse_state = PARSE_WAIT_LEN;
            end
            PARSE_WAIT_LEN : begin
                latch_len = 1'b1;
                if (card_info_rd_vld) begin
                    if (parse_idx < card_info_len) nxt_parse_state = PARSE_TEST_LEN;
                    else                           nxt_parse_state = PARSE_ERROR;
                end
            end
            PARSE_TEST_LEN : begin
                if (parse_len > 0 && (parse_idx + parse_len) <= card_info_len) nxt_parse_state = PARSE_EVAL;
                else                                                           nxt_parse_state = PARSE_ERROR;
            end
            PARSE_EVAL : begin
                if (found_key == parse_key)                      nxt_parse_state = PARSE_DONE;
                else if (parse_idx + parse_len == card_info_len) nxt_parse_state = PARSE_KEY_NOT_FOUND;
                else                                             nxt_parse_state = PARSE_SKIP_VALUE;
            end
            PARSE_SKIP_VALUE : begin
                parse_idx_incr = parse_len;
                nxt_parse_state = PARSE_GET_KEY;
            end
            PARSE_KEY_NOT_FOUND : begin
                nxt_parse_state = PARSE_ERROR;
            end
            PARSE_DONE : begin
                nxt_parse_state = PARSE_IDLE;
            end
            PARSE_ERROR : begin
                nxt_parse_state = PARSE_IDLE;
            end
        endcase
    end

    // Manage pointer into cardinfo data structure
    always_ff @(posedge clk) begin
        if (reset_parse_idx) parse_idx <= 0;
        else                 parse_idx <= parse_idx + parse_idx_incr;
    end

    // Latch key/length from current cardinfo record
    always_ff @(posedge clk) if (card_info_rd_vld && latch_key) found_key <= card_info_rd_data;
    always_ff @(posedge clk) if (card_info_rd_vld && latch_len) parse_len <= card_info_rd_data;

    // VPD Access Mux
    
    // No need to arbitrate write access (yet), since VPD writes (from external controller
    // are not supported. Could add this but generally these writes would end up in NV RAM,
    // whereas this VPD data struture would last only until the next reset/power cycle

    // Read
    // Need to arbitrate here between read requests coming from PCIe extended config
    // interface and initialization reads
    always_comb begin
        case (state)
            DONE: begin
                vpd_ram_req     = vpd_req && !vpd_wr_rd_n;
                vpd_ram_wr_rd_n = 1'b0;
                vpd_ram_addr    = vpd_addr > VPD_ROM_SIZE-1 ? vpd_addr - VPD_ROM_SIZE : 0;
                vpd_ram_wr_data = '0;
            end
            ERROR: begin
                vpd_ram_req     = 1'b0;
                vpd_ram_wr_rd_n = 1'b0;
                vpd_ram_addr    = '0;
                vpd_ram_wr_data = '0;
            end
            default : begin
                vpd_ram_req     = vpd_init_wr || vpd_init_rd;
                vpd_ram_wr_rd_n = vpd_init_wr;
                vpd_ram_addr    = {'0, vpd_init_idx};
                vpd_ram_wr_data = vpd_init_wr_data;
            end
        endcase
    end

    initial vpd_rd_vld = 1'b0;
    always @(posedge clk) begin
        if (srst) vpd_rd_vld <= 1'b0;
        else begin
            if (vpd_req && !vpd_wr_rd_n) vpd_rd_vld <= 1'b1;
            else                         vpd_rd_vld <= 1'b0;
        end
    end

    always @(posedge clk) if (vpd_req) vpd_addr_r <= vpd_addr;

    initial VPD_RAM = '{default: 8'h0};
    always @(posedge clk) begin
        if (vpd_ram_req && vpd_ram_addr < VPD_MAX_LEN) begin
            if (vpd_ram_wr_rd_n) VPD_RAM[vpd_ram_addr[VPD_IDX_WID-1:0]] <= vpd_ram_wr_data;
            else vpd_ram_rd_data <= VPD_RAM[vpd_ram_addr[VPD_IDX_WID-1:0]];
        end
    end

    always_comb begin
        vpd_rd_data = 8'hff;
        if (__init_done && vpd_addr_r < VPD_MAX_LEN) begin
            if (vpd_addr_r == VPD_MAX_LEN-1)    vpd_rd_data = VPD_SRDT_END;
            else if (vpd_addr_r < VPD_ROM_SIZE) vpd_rd_data = vpd_rom_rd_data;
            else                                vpd_rd_data = vpd_ram_rd_data;
        end
    end

    assign vpd_init_rd_data = vpd_ram_rd_data;

    // Drive init_* status outputs
    always_ff @(posedge clk) begin
        init_done <= __init_done;
        init_error <= __init_error;
    end

endmodule : system_config_vpd
