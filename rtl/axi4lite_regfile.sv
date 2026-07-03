//==============================================================================
// axi4lite_regfile.sv  (Week 3)
// AXI4-Lite slave wrapping a 16 x 32b control/status register file.
//
// Week 3 additions on top of Week 2:
//   - SLVERR on reserved-address writes (BRESP)
//   - SLVERR on reserved-address reads  (RRESP)
//   - 5 SVA protocol assertions (VALID stability, payload stability)
//==============================================================================
module axi4lite_regfile
    import axi4lite_regfile_pkg::*;
#(
    parameter int ADDR_WIDTH = 6,
    parameter int DATA_WIDTH = 32
) (
    input  logic                        aclk,
    input  logic                        aresetn,

    // Write address
    input  logic [ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  logic [2:0]                  s_axi_awprot,
    input  logic                        s_axi_awvalid,
    output logic                        s_axi_awready,

    // Write data
    input  logic [DATA_WIDTH-1:0]       s_axi_wdata,
    input  logic [(DATA_WIDTH/8)-1:0]   s_axi_wstrb,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,

    // Write response
    output logic [1:0]                  s_axi_bresp,
    output logic                        s_axi_bvalid,
    input  logic                        s_axi_bready,

    // Read address
    input  logic [ADDR_WIDTH-1:0]       s_axi_araddr,
    input  logic [2:0]                  s_axi_arprot,
    input  logic                        s_axi_arvalid,
    output logic                        s_axi_arready,

    // Read data
    output logic [DATA_WIDTH-1:0]       s_axi_rdata,
    output logic [1:0]                  s_axi_rresp,
    output logic                        s_axi_rvalid,
    input  logic                        s_axi_rready,

    // Hardware side
    input  logic [DATA_WIDTH-1:0]       hw_status_i,
    input  logic [DATA_WIDTH-1:0]       irq_set_i,
    output logic                        irq_o
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    //==========================================================================
    // WRITE CHANNEL FSM
    //==========================================================================
    typedef enum logic [1:0] {
        W_IDLE      = 2'b00,
        W_WAIT_W    = 2'b01,
        W_WAIT_AW   = 2'b10,
        W_RESP      = 2'b11
    } write_state_t;

    write_state_t w_state, w_next;

    logic [ADDR_WIDTH-1:0]  awaddr_q;
    logic [DATA_WIDTH-1:0]  wdata_q;
    logic [STRB_WIDTH-1:0]  wstrb_q;

    wire aw_hs = s_axi_awvalid & s_axi_awready;
    wire w_hs  = s_axi_wvalid  & s_axi_wready;

    always_comb begin
        w_next = w_state;
        unique case (w_state)
            W_IDLE: begin
                if (s_axi_awvalid && s_axi_wvalid) w_next = W_RESP;
                else if (s_axi_awvalid)            w_next = W_WAIT_W;
                else if (s_axi_wvalid)             w_next = W_WAIT_AW;
            end
            W_WAIT_W:  if (s_axi_wvalid)  w_next = W_RESP;
            W_WAIT_AW: if (s_axi_awvalid) w_next = W_RESP;
            W_RESP:    if (s_axi_bready)  w_next = W_IDLE;
        endcase
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) w_state <= W_IDLE;
        else          w_state <= w_next;
    end

    assign s_axi_awready = (w_state == W_IDLE) || (w_state == W_WAIT_AW);
    assign s_axi_wready  = (w_state == W_IDLE) || (w_state == W_WAIT_W);
    assign s_axi_bvalid  = (w_state == W_RESP);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            awaddr_q <= '0;
            wdata_q  <= '0;
            wstrb_q  <= '0;
        end else begin
            if (aw_hs) awaddr_q <= s_axi_awaddr;
            if (w_hs)  begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
            end
        end
    end

    wire reg_wr_en = (w_state != W_RESP) && (w_next == W_RESP);
    wire [3:0]              wr_addr = aw_hs ? s_axi_awaddr[5:2] : awaddr_q[5:2];
    wire [DATA_WIDTH-1:0]   wr_data = w_hs  ? s_axi_wdata       : wdata_q;
    wire [STRB_WIDTH-1:0]   wr_strb = w_hs  ? s_axi_wstrb       : wstrb_q;

    //--------------------------------------------------------------------------
    // Reserved-address SLVERR decode (Week 3)
    //--------------------------------------------------------------------------
    // BRESP is derived from the latched awaddr_q. Master only samples BRESP
    // while BVALID is high (W_RESP), by which time awaddr_q reflects the
    // current transaction.
    wire wr_slverr = (awaddr_q[5:2] == ADDR_RESERVED_0) ||
                     (awaddr_q[5:2] == ADDR_RESERVED_1);

    assign s_axi_bresp = wr_slverr ? AXI_RESP_SLVERR : AXI_RESP_OKAY;

    function automatic logic [DATA_WIDTH-1:0] apply_wstrb(
        input logic [DATA_WIDTH-1:0]  current,
        input logic [DATA_WIDTH-1:0]  new_data,
        input logic [STRB_WIDTH-1:0]  strb
    );
        logic [DATA_WIDTH-1:0] result;
        for (int b = 0; b < STRB_WIDTH; b++)
            result[b*8 +: 8] = strb[b] ? new_data[b*8 +: 8] : current[b*8 +: 8];
        return result;
    endfunction

    //==========================================================================
    // REGISTER BANK
    //==========================================================================
    logic [DATA_WIDTH-1:0] reg_scratch0, reg_scratch1, reg_scratch2, reg_scratch3;
    logic [DATA_WIDTH-1:0] reg_ctrl, reg_config, reg_mode;
    logic [DATA_WIDTH-1:0] reg_irq_enable;
    logic [DATA_WIDTH-1:0] reg_irq_status;
    logic [63:0]           counter;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            reg_scratch0   <= '0;
            reg_scratch1   <= '0;
            reg_scratch2   <= '0;
            reg_scratch3   <= '0;
            reg_ctrl       <= '0;
            reg_config     <= '0;
            reg_mode       <= '0;
            reg_irq_enable <= '0;
        end else if (reg_wr_en) begin
            case (wr_addr)
                ADDR_SCRATCH0:    reg_scratch0   <= apply_wstrb(reg_scratch0,   wr_data, wr_strb);
                ADDR_SCRATCH1:    reg_scratch1   <= apply_wstrb(reg_scratch1,   wr_data, wr_strb);
                ADDR_SCRATCH2:    reg_scratch2   <= apply_wstrb(reg_scratch2,   wr_data, wr_strb);
                ADDR_SCRATCH3:    reg_scratch3   <= apply_wstrb(reg_scratch3,   wr_data, wr_strb);
                ADDR_CTRL:        reg_ctrl       <= apply_wstrb(reg_ctrl,       wr_data, wr_strb);
                ADDR_CONFIG:      reg_config     <= apply_wstrb(reg_config,     wr_data, wr_strb);
                ADDR_MODE:        reg_mode       <= apply_wstrb(reg_mode,       wr_data, wr_strb);
                ADDR_IRQ_ENABLE:  reg_irq_enable <= apply_wstrb(reg_irq_enable, wr_data, wr_strb);
                // IRQ_STATUS -> W1C handled below
                // RO / reserved -> no-op (SLVERR flagged in bresp path)
                default: /* no-op */;
            endcase
        end
    end

    // IRQ_STATUS (W1C, hardware-set wins)
    logic [DATA_WIDTH-1:0] irq_clear_mask;
    always_comb begin
        irq_clear_mask = '0;
        if (reg_wr_en && (wr_addr == ADDR_IRQ_STATUS)) begin
            for (int b = 0; b < STRB_WIDTH; b++)
                if (wr_strb[b])
                    irq_clear_mask[b*8 +: 8] = wr_data[b*8 +: 8];
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) reg_irq_status <= '0;
        else          reg_irq_status <= (reg_irq_status & ~irq_clear_mask) | irq_set_i;
    end

    // Free-running counter
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) counter <= '0;
        else          counter <= counter + 64'd1;
    end

    // Aggregated interrupt output
    assign irq_o = |(reg_irq_status & reg_irq_enable);

    //==========================================================================
    // READ CHANNEL FSM
    //==========================================================================
    typedef enum logic {R_IDLE, R_RESP} read_state_t;
    read_state_t r_state, r_next;

    always_comb begin
        r_next = r_state;
        unique case (r_state)
            R_IDLE:  if (s_axi_arvalid) r_next = R_RESP;
            R_RESP:  if (s_axi_rready)  r_next = R_IDLE;
        endcase
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) r_state <= R_IDLE;
        else          r_state <= r_next;
    end

    assign s_axi_arready = (r_state == R_IDLE);
    assign s_axi_rvalid  = (r_state == R_RESP);

    wire ar_hs = s_axi_arvalid & s_axi_arready;

    logic [DATA_WIDTH-1:0]  rdata_mux;
    wire  [3:0]             rd_addr = s_axi_araddr[5:2];

    always_comb begin
        case (rd_addr)
            ADDR_SCRATCH0:    rdata_mux = reg_scratch0;
            ADDR_SCRATCH1:    rdata_mux = reg_scratch1;
            ADDR_SCRATCH2:    rdata_mux = reg_scratch2;
            ADDR_SCRATCH3:    rdata_mux = reg_scratch3;
            ADDR_CTRL:        rdata_mux = reg_ctrl;
            ADDR_CONFIG:      rdata_mux = reg_config;
            ADDR_MODE:        rdata_mux = reg_mode;
            ADDR_STATUS:      rdata_mux = hw_status_i;
            ADDR_VERSION:     rdata_mux = VERSION_VALUE;
            ADDR_COUNTER_LO:  rdata_mux = counter[31:0];
            ADDR_COUNTER_HI:  rdata_mux = counter[63:32];
            ADDR_IRQ_STATUS:  rdata_mux = reg_irq_status;
            ADDR_IRQ_ENABLE:  rdata_mux = reg_irq_enable;
            ADDR_IRQ_RAW:     rdata_mux = irq_set_i;
            default:          rdata_mux = '0;   // Reserved -> RRESP=SLVERR
        endcase
    end

    // Reserved-address decode for reads (Week 3)
    wire rd_slverr = (rd_addr == ADDR_RESERVED_0) || (rd_addr == ADDR_RESERVED_1);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_rdata <= '0;
            s_axi_rresp <= AXI_RESP_OKAY;
        end else if (ar_hs) begin
            s_axi_rdata <= rdata_mux;
            s_axi_rresp <= rd_slverr ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
        end
    end

    //==========================================================================
    // AXI PROTOCOL ASSERTIONS (SVA) -- Week 3
    //==========================================================================
`ifndef SYNTHESIS

    property p_aw_stable;
        @(posedge aclk) disable iff (!aresetn)
            (s_axi_awvalid && !s_axi_awready) |=>
                (s_axi_awvalid && $stable(s_axi_awaddr) && $stable(s_axi_awprot));
    endproperty
    a_aw_stable: assert property (p_aw_stable)
        else $error("AXI: AW payload changed or awvalid dropped mid-handshake");

    property p_w_stable;
        @(posedge aclk) disable iff (!aresetn)
            (s_axi_wvalid && !s_axi_wready) |=>
                (s_axi_wvalid && $stable(s_axi_wdata) && $stable(s_axi_wstrb));
    endproperty
    a_w_stable: assert property (p_w_stable)
        else $error("AXI: W payload changed or wvalid dropped mid-handshake");

    property p_b_stable;
        @(posedge aclk) disable iff (!aresetn)
            (s_axi_bvalid && !s_axi_bready) |=>
                (s_axi_bvalid && $stable(s_axi_bresp));
    endproperty
    a_b_stable: assert property (p_b_stable)
        else $error("AXI: BRESP changed or bvalid dropped mid-handshake");

    property p_ar_stable;
        @(posedge aclk) disable iff (!aresetn)
            (s_axi_arvalid && !s_axi_arready) |=>
                (s_axi_arvalid && $stable(s_axi_araddr) && $stable(s_axi_arprot));
    endproperty
    a_ar_stable: assert property (p_ar_stable)
        else $error("AXI: AR payload changed or arvalid dropped mid-handshake");

    property p_r_stable;
        @(posedge aclk) disable iff (!aresetn)
            (s_axi_rvalid && !s_axi_rready) |=>
                (s_axi_rvalid && $stable(s_axi_rdata) && $stable(s_axi_rresp));
    endproperty
    a_r_stable: assert property (p_r_stable)
        else $error("AXI: R payload changed or rvalid dropped mid-handshake");

`endif

endmodule
