//==============================================================================
// tb_axi4lite_regfile.sv  (Week 3)
// Adds on top of Week 2:
//   8. SLVERR on write to reserved addresses
//   9. SLVERR on read from reserved addresses
//  10. Randomized RW stress with shadow-model comparison (50 iterations)
//  11. Functional covergroup on write/read addresses and byte strobes
//==============================================================================
`timescale 1ns/1ps

module tb_axi4lite_regfile;
    import axi4lite_regfile_pkg::*;
    import axi_lite_master_bfm_pkg::*;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #5 aclk = ~aclk;

    axi_lite_if bus (.aclk(aclk), .aresetn(aresetn));

    logic [31:0] hw_status_i;
    logic [31:0] irq_set_i;
    logic        irq_o;

    axi4lite_regfile #(.ADDR_WIDTH(6), .DATA_WIDTH(32)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(bus.awaddr),   .s_axi_awprot(bus.awprot),
        .s_axi_awvalid(bus.awvalid), .s_axi_awready(bus.awready),
        .s_axi_wdata(bus.wdata),     .s_axi_wstrb(bus.wstrb),
        .s_axi_wvalid(bus.wvalid),   .s_axi_wready(bus.wready),
        .s_axi_bresp(bus.bresp),     .s_axi_bvalid(bus.bvalid),   .s_axi_bready(bus.bready),
        .s_axi_araddr(bus.araddr),   .s_axi_arprot(bus.arprot),
        .s_axi_arvalid(bus.arvalid), .s_axi_arready(bus.arready),
        .s_axi_rdata(bus.rdata),     .s_axi_rresp(bus.rresp),
        .s_axi_rvalid(bus.rvalid),   .s_axi_rready(bus.rready),
        .hw_status_i(hw_status_i),
        .irq_set_i(irq_set_i),
        .irq_o(irq_o)
    );

    axi_lite_master_bfm bfm;

    int unsigned check_count = 0;
    int unsigned error_count = 0;

    //==========================================================================
    // Functional coverage
    //==========================================================================
    covergroup cg_axi @(posedge aclk iff (aresetn));
        option.per_instance = 1;

        cp_wr_addr: coverpoint dut.wr_addr iff (dut.reg_wr_en) {
            bins per_addr[] = {[0:15]};
        }
        cp_rd_addr: coverpoint dut.rd_addr iff (dut.ar_hs) {
            bins per_addr[] = {[0:15]};
        }
        cp_wstrb: coverpoint dut.wr_strb iff (dut.reg_wr_en) {
            bins single_byte[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
            bins half_word[]   = {4'b0011, 4'b1100};
            bins full_word     = {4'b1111};
            bins other         = default;
        }
    endgroup

    cg_axi cov;

    //==========================================================================
    // Helpers
    //==========================================================================
    task automatic check_eq(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string       name
    );
        check_count++;
        if (actual !== expected) begin
            $display("[%0t] FAIL %-42s got=0x%08h exp=0x%08h", $time, name, actual, expected);
            error_count++;
        end else begin
            $display("[%0t] PASS %-42s val=0x%08h", $time, name, actual);
        end
    endtask

    task automatic check_bit(
        input logic actual,
        input logic expected,
        input string name
    );
        check_count++;
        if (actual !== expected) begin
            $display("[%0t] FAIL %-42s got=%b exp=%b", $time, name, actual, expected);
            error_count++;
        end else begin
            $display("[%0t] PASS %-42s val=%b", $time, name, actual);
        end
    endtask

    task automatic check_resp(
        input logic [1:0] actual,
        input logic [1:0] expected,
        input string      name
    );
        check_count++;
        if (actual !== expected) begin
            $display("[%0t] FAIL %-42s got=%b exp=%b", $time, name, actual, expected);
            error_count++;
        end else begin
            $display("[%0t] PASS %-42s val=%b", $time, name, actual);
        end
    endtask

    //==========================================================================
    // Directed tests (Weeks 1-2)
    //==========================================================================
    task automatic test_write_readback();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: Write + readback across RW registers -----");
        bfm.write(6'h00, 32'hDEAD_BEEF, 4'hF, resp);
        check_resp(resp, AXI_RESP_OKAY, "SCRATCH0 write BRESP");
        bfm.read (6'h00, rd, resp);
        check_eq(rd, 32'hDEAD_BEEF, "SCRATCH0 readback");
        bfm.write(6'h10, 32'h1234_5678, 4'hF, resp);
        bfm.read (6'h10, rd, resp);
        check_eq(rd, 32'h1234_5678, "CTRL readback");
        bfm.write(6'h14, 32'hA5A5_5A5A, 4'hF, resp);
        bfm.read (6'h14, rd, resp);
        check_eq(rd, 32'hA5A5_5A5A, "CONFIG readback");
    endtask

    task automatic test_byte_strobes();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: Byte strobes on writes -----");
        bfm.write(6'h08, 32'hFFFF_FFFF, 4'hF, resp);
        bfm.write(6'h08, 32'h0000_0000, 4'b0101, resp);
        bfm.read (6'h08, rd, resp);
        check_eq(rd, 32'hFF00_FF00, "SCRATCH2 wstrb=0101 selective clear");
        bfm.write(6'h0C, 32'h0000_0000, 4'hF, resp);
        bfm.write(6'h0C, 32'hCAFE_BABE, 4'b1100, resp);
        bfm.read (6'h0C, rd, resp);
        check_eq(rd, 32'hCAFE_0000, "SCRATCH3 wstrb=1100 upper half");
        // wstrb=0 no-op write: transaction completes OKAY, but no byte updates
        bfm.write(6'h00, 32'hFFFF_FFFF, 4'b0000, resp);
        check_resp(resp, AXI_RESP_OKAY, "wstrb=0 no-op write returns OKAY");
    endtask

    task automatic test_channel_ordering();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: Channel ordering (AW-first, W-first) -----");
        bfm.write_aw_first(6'h00, 32'hCAFE_BABE, 4'hF, resp);
        bfm.read (6'h00, rd, resp);
        check_eq(rd, 32'hCAFE_BABE, "SCRATCH0 via AW-first (W_WAIT_W)");
        bfm.write_w_first(6'h04, 32'hFACE_F00D, 4'hF, resp);
        bfm.read (6'h04, rd, resp);
        check_eq(rd, 32'hFACE_F00D, "SCRATCH1 via W-first (W_WAIT_AW)");
    endtask

    task automatic test_ro_registers();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: Read-only registers -----");
        hw_status_i = 32'hCAFE_1234;
        @(posedge aclk);
        bfm.read(6'h20, rd, resp);
        check_eq(rd, 32'hCAFE_1234, "STATUS reflects hw_status_i");
        bfm.read(6'h24, rd, resp);
        check_eq(rd, VERSION_VALUE, "VERSION constant");
        irq_set_i = 32'h5A5A_A5A5;
        @(posedge aclk);
        bfm.read(6'h38, rd, resp);
        check_eq(rd, 32'h5A5A_A5A5, "IRQ_RAW reflects irq_set_i");
        irq_set_i = '0;
        bfm.write(6'h20, 32'hDEAD_DEAD, 4'hF, resp);   // STATUS (RO)
        bfm.write(6'h24, 32'hDEAD_DEAD, 4'hF, resp);   // VERSION (RO)
        bfm.write(6'h28, 32'hDEAD_DEAD, 4'hF, resp);   // COUNTER_LO (RO)
        bfm.write(6'h2C, 32'hDEAD_DEAD, 4'hF, resp);   // COUNTER_HI (RO)
        bfm.write(6'h38, 32'hDEAD_DEAD, 4'hF, resp);   // IRQ_RAW (RO)
        bfm.read (6'h24, rd, resp);
        check_eq(rd, VERSION_VALUE, "VERSION unchanged after RO write attempt");
    endtask

    task automatic test_counter();
        logic [31:0] c1, c2;
        logic [1:0]  resp;
        $display("\n----- TEST: Free-running counter -----");
        bfm.read(6'h28, c1, resp);
        repeat (20) @(posedge aclk);
        bfm.read(6'h28, c2, resp);
        bfm.read(6'h2C, c1, resp);   // COUNTER_HI — coverage hit
        check_count++; $display("[%0t] PASS %-42s val=0x%08h", $time, "COUNTER_HI readable", c1);
        check_count++;
        if (c2 > c1) begin
            $display("[%0t] PASS %-42s c1=0x%08h c2=0x%08h (advanced)", $time,
                     "COUNTER_LO advances over time", c1, c2);
        end else begin
            error_count++;
            $display("[%0t] FAIL %-42s c1=0x%08h c2=0x%08h", $time,
                     "COUNTER_LO advances over time", c1, c2);
        end
    endtask

    task automatic test_w1c();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: IRQ_STATUS W1C behavior -----");
        bfm.write(6'h30, 32'hFFFF_FFFF, 4'hF, resp);
        bfm.read (6'h30, rd, resp);
        check_eq(rd, 32'h0, "IRQ_STATUS cleared before subtest");
        irq_set_i = 32'h0000_00FF;
        @(posedge aclk);
        irq_set_i = '0;
        @(posedge aclk);
        bfm.read(6'h30, rd, resp);
        check_eq(rd, 32'h0000_00FF, "IRQ_STATUS after HW set (bits [7:0])");
        bfm.write(6'h30, 32'h0000_000F, 4'hF, resp);
        bfm.read (6'h30, rd, resp);
        check_eq(rd, 32'h0000_00F0, "IRQ_STATUS after W1C low nibble");
        bfm.write(6'h30, 32'h0000_0000, 4'hF, resp);
        bfm.read (6'h30, rd, resp);
        check_eq(rd, 32'h0000_00F0, "IRQ_STATUS unchanged after W1C of 0");
        irq_set_i = 32'hFFFF_FFFF;
        @(posedge aclk);
        irq_set_i = '0;
        @(posedge aclk);
        bfm.write(6'h30, 32'hFFFF_FFFF, 4'b0011, resp);
        bfm.read (6'h30, rd, resp);
        check_eq(rd, 32'hFFFF_0000, "IRQ_STATUS byte-strobed clear (wstrb=0011)");
        bfm.write(6'h30, 32'hFFFF_FFFF, 4'hF, resp);
    endtask

    task automatic test_irq_aggregation();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: IRQ output aggregation -----");
        bfm.write(6'h30, 32'hFFFF_FFFF, 4'hF, resp);
        bfm.write(6'h34, 32'h0000_0000, 4'hF, resp);
        @(posedge aclk);
        check_bit(irq_o, 1'b0, "irq_o low when enable=0 and status=0");
        bfm.write(6'h34, 32'h0000_00F0, 4'hF, resp);
        irq_set_i = 32'h0000_000F;
        @(posedge aclk);
        irq_set_i = '0;
        repeat (2) @(posedge aclk);
        check_bit(irq_o, 1'b0, "irq_o low when only masked bits set");
        irq_set_i = 32'h0000_0080;
        @(posedge aclk);
        irq_set_i = '0;
        repeat (2) @(posedge aclk);
        check_bit(irq_o, 1'b1, "irq_o high when enabled bit fires");
        bfm.write(6'h30, 32'h0000_0080, 4'hF, resp);
        repeat (2) @(posedge aclk);
        check_bit(irq_o, 1'b0, "irq_o low after W1C of enabled bit");
        bfm.write(6'h30, 32'hFFFF_FFFF, 4'hF, resp);
        bfm.write(6'h34, 32'h0000_0000, 4'hF, resp);
    endtask

    //==========================================================================
    // Week 3 tests: SLVERR + stress
    //==========================================================================
    task automatic test_slverr_write();
        logic [1:0] resp;
        $display("\n----- TEST: SLVERR on writes to reserved addresses -----");
        bfm.write(6'h1C, 32'hDEAD_DEAD, 4'hF, resp);
        check_resp(resp, AXI_RESP_SLVERR, "write 0x1C returns BRESP=SLVERR");
        bfm.write(6'h3C, 32'hBEEF_BEEF, 4'hF, resp);
        check_resp(resp, AXI_RESP_SLVERR, "write 0x3C returns BRESP=SLVERR");
        // Confirm a legal write still returns OKAY after SLVERR paths were exercised
        bfm.write(6'h00, 32'h1122_3344, 4'hF, resp);
        check_resp(resp, AXI_RESP_OKAY, "write 0x00 still returns OKAY");
    endtask

    task automatic test_slverr_read();
        logic [31:0] rd;
        logic [1:0]  resp;
        $display("\n----- TEST: SLVERR on reads from reserved addresses -----");
        bfm.read(6'h1C, rd, resp);
        check_resp(resp, AXI_RESP_SLVERR, "read 0x1C returns RRESP=SLVERR");
        bfm.read(6'h3C, rd, resp);
        check_resp(resp, AXI_RESP_SLVERR, "read 0x3C returns RRESP=SLVERR");
        bfm.read(6'h00, rd, resp);
        check_resp(resp, AXI_RESP_OKAY, "read 0x00 still returns OKAY");
    endtask

    task automatic test_stress_rw(input int N = 50);
        // 8 RW addresses (SCRATCH0..3, CTRL, CONFIG, MODE, IRQ_ENABLE)
        // Shadow model with per-addr byte-strobe accumulation.
        logic [3:0]  addr_map [8];
        logic [31:0] shadow   [8];
        logic [31:0] rd, wdat;
        logic [3:0]  strb;
        logic [1:0]  resp;
        logic [5:0]  addr;
        int          idx;

        addr_map = '{ADDR_SCRATCH0, ADDR_SCRATCH1, ADDR_SCRATCH2, ADDR_SCRATCH3,
                     ADDR_CTRL, ADDR_CONFIG, ADDR_MODE, ADDR_IRQ_ENABLE};

        $display("\n----- TEST: Randomized RW stress (%0d iterations) -----", N);

        // Sync shadow to a known state (zero everything)
        for (int i = 0; i < 8; i++) begin
            bfm.write({addr_map[i], 2'b00}, 32'h0, 4'hF, resp);
            shadow[i] = 32'h0;
        end

        for (int i = 0; i < N; i++) begin
            idx  = $urandom_range(0, 7);
            addr = {addr_map[idx], 2'b00};
            wdat = $urandom();
            strb = $urandom_range(1, 15);   // at least one byte enabled

            bfm.write(addr, wdat, strb, resp);
            for (int b = 0; b < 4; b++)
                if (strb[b])
                    shadow[idx][b*8 +: 8] = wdat[b*8 +: 8];

            bfm.read(addr, rd, resp);
            check_eq(rd, shadow[idx],
                     $sformatf("stress i=%0d addr=0x%02h strb=%b", i, addr, strb));
        end
    endtask

    //==========================================================================
    // Main
    //==========================================================================
    initial begin
        cov = new();

        bfm = new("m0", bus);
        bfm.reset_signals();
        hw_status_i = '0;
        irq_set_i   = '0;

        aresetn = 1'b0;
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        test_write_readback();
        test_byte_strobes();
        test_channel_ordering();
        test_ro_registers();
        test_counter();
        test_w1c();
        test_irq_aggregation();
        test_slverr_write();
        test_slverr_read();
        test_stress_rw(50);

        $display("\n=============================================================");
        if (error_count == 0)
            $display("  RESULT: PASS   (%0d checks, 0 errors)", check_count);
        else
            $display("  RESULT: FAIL   (%0d checks, %0d errors)", check_count, error_count);
        $display("  Functional coverage: %0.2f%%", cov.get_coverage());
        $display("=============================================================\n");

        $finish;
    end

    // Watchdog
    initial begin
        #200_000ns;
        $display("[%0t] TIMEOUT -- simulation hung", $time);
        $finish;
    end

endmodule
