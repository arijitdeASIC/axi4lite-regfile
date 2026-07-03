//==============================================================================
// axi4lite_regfile_pkg.sv
// Register map constants and AXI response codes for axi4lite_regfile.
//==============================================================================
package axi4lite_regfile_pkg;

    // Word-offset addresses (byte_addr[5:2])
    localparam logic [3:0] ADDR_SCRATCH0    = 4'h0;  // 0x00 RW
    localparam logic [3:0] ADDR_SCRATCH1    = 4'h1;  // 0x04 RW
    localparam logic [3:0] ADDR_SCRATCH2    = 4'h2;  // 0x08 RW
    localparam logic [3:0] ADDR_SCRATCH3    = 4'h3;  // 0x0C RW
    localparam logic [3:0] ADDR_CTRL        = 4'h4;  // 0x10 RW
    localparam logic [3:0] ADDR_CONFIG      = 4'h5;  // 0x14 RW
    localparam logic [3:0] ADDR_MODE        = 4'h6;  // 0x18 RW
    localparam logic [3:0] ADDR_RESERVED_0  = 4'h7;  // 0x1C -> SLVERR (Week 3)
    localparam logic [3:0] ADDR_STATUS      = 4'h8;  // 0x20 RO (Week 2)
    localparam logic [3:0] ADDR_VERSION     = 4'h9;  // 0x24 RO (Week 2)
    localparam logic [3:0] ADDR_COUNTER_LO  = 4'hA;  // 0x28 RO (Week 2)
    localparam logic [3:0] ADDR_COUNTER_HI  = 4'hB;  // 0x2C RO (Week 2)
    localparam logic [3:0] ADDR_IRQ_STATUS  = 4'hC;  // 0x30 W1C (Week 2)
    localparam logic [3:0] ADDR_IRQ_ENABLE  = 4'hD;  // 0x34 RW
    localparam logic [3:0] ADDR_IRQ_RAW     = 4'hE;  // 0x38 RO (Week 2)
    localparam logic [3:0] ADDR_RESERVED_1  = 4'hF;  // 0x3C -> SLVERR (Week 3)

    localparam logic [31:0] VERSION_VALUE   = 32'h0001_0000;

    // AXI response codes (spec IHI 0022, section A3.4.4)
    localparam logic [1:0] AXI_RESP_OKAY    = 2'b00;
    localparam logic [1:0] AXI_RESP_EXOKAY  = 2'b01;
    localparam logic [1:0] AXI_RESP_SLVERR  = 2'b10;
    localparam logic [1:0] AXI_RESP_DECERR  = 2'b11;

endpackage
