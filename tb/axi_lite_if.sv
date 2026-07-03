//==============================================================================
// axi_lite_if.sv
// AXI4-Lite bundle for TB / BFM use. Hardcoded to 6-bit addr, 32-bit data
// to match the axi4lite_regfile DUT parameters.
//==============================================================================
interface axi_lite_if (
    input logic aclk,
    input logic aresetn
);
    // Write address
    logic [5:0]  awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;
    // Write data
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    // Write response
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    // Read address
    logic [5:0]  araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;
    // Read data
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;
endinterface
