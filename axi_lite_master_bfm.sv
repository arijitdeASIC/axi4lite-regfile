//==============================================================================
// axi_lite_master_bfm.sv
// Class-based AXI4-Lite master BFM. Uses a virtual axi_lite_if handle so a
// single BFM instance drives the DUT via any interface bound at TB build time.
//
// Public API (tasks):
//   reset_signals()                        - drive all master outputs to safe idle
//   write(addr, data, strb, resp)          - simultaneous AW+W issue
//   write_aw_first(addr, data, strb, resp, gap)
//   write_w_first (addr, data, strb, resp, gap)
//   read(addr, data, resp)                 - single-beat read
//==============================================================================
package axi_lite_master_bfm_pkg;
    import axi4lite_regfile_pkg::*;

    class axi_lite_master_bfm;

        virtual axi_lite_if vif;
        string              name;

        function new(string name, virtual axi_lite_if vif);
            this.name = name;
            this.vif  = vif;
        endfunction

        //----------------------------------------------------------------------
        // reset_signals: drive all master outputs to safe idle values
        //----------------------------------------------------------------------
        task automatic reset_signals();
            vif.awaddr  <= '0;  vif.awprot <= '0;  vif.awvalid <= 1'b0;
            vif.wdata   <= '0;  vif.wstrb  <= '0;  vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.araddr  <= '0;  vif.arprot <= '0;  vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;
        endtask

        //----------------------------------------------------------------------
        // write: simultaneous AW+W (fastest path through the slave FSM)
        //----------------------------------------------------------------------
        task automatic write(
            input  logic [5:0]  addr,
            input  logic [31:0] data,
            input  logic [3:0]  strb,
            output logic [1:0]  resp
        );
            @(posedge vif.aclk);
            vif.awaddr  <= addr;  vif.awprot <= 3'b000;  vif.awvalid <= 1'b1;
            vif.wdata   <= data;  vif.wstrb  <= strb;    vif.wvalid  <= 1'b1;
            vif.bready  <= 1'b1;

            fork
                begin
                    do @(posedge vif.aclk); while (!vif.awready);
                    vif.awvalid <= 1'b0;
                end
                begin
                    do @(posedge vif.aclk); while (!vif.wready);
                    vif.wvalid <= 1'b0;
                end
            join

            while (!vif.bvalid) @(posedge vif.aclk);
            resp = vif.bresp;
            @(posedge vif.aclk);
            vif.bready <= 1'b0;
        endtask

        //----------------------------------------------------------------------
        // write_aw_first: AW handshake, gap cycles, then W
        //----------------------------------------------------------------------
        task automatic write_aw_first(
            input  logic [5:0]  addr,
            input  logic [31:0] data,
            input  logic [3:0]  strb,
            output logic [1:0]  resp,
            input  int          gap = 3
        );
            @(posedge vif.aclk);
            vif.awaddr <= addr;  vif.awprot <= 3'b000;  vif.awvalid <= 1'b1;
            do @(posedge vif.aclk); while (!vif.awready);
            vif.awvalid <= 1'b0;

            repeat (gap) @(posedge vif.aclk);

            vif.wdata <= data;  vif.wstrb <= strb;  vif.wvalid <= 1'b1;
            vif.bready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.wready);
            vif.wvalid <= 1'b0;

            while (!vif.bvalid) @(posedge vif.aclk);
            resp = vif.bresp;
            @(posedge vif.aclk);
            vif.bready <= 1'b0;
        endtask

        //----------------------------------------------------------------------
        // write_w_first: W handshake, gap cycles, then AW
        //----------------------------------------------------------------------
        task automatic write_w_first(
            input  logic [5:0]  addr,
            input  logic [31:0] data,
            input  logic [3:0]  strb,
            output logic [1:0]  resp,
            input  int          gap = 3
        );
            @(posedge vif.aclk);
            vif.wdata <= data;  vif.wstrb <= strb;  vif.wvalid <= 1'b1;
            do @(posedge vif.aclk); while (!vif.wready);
            vif.wvalid <= 1'b0;

            repeat (gap) @(posedge vif.aclk);

            vif.awaddr <= addr;  vif.awprot <= 3'b000;  vif.awvalid <= 1'b1;
            vif.bready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.awready);
            vif.awvalid <= 1'b0;

            while (!vif.bvalid) @(posedge vif.aclk);
            resp = vif.bresp;
            @(posedge vif.aclk);
            vif.bready <= 1'b0;
        endtask

        //----------------------------------------------------------------------
        // read: single-beat AR/R
        //----------------------------------------------------------------------
        task automatic read(
            input  logic [5:0]  addr,
            output logic [31:0] data,
            output logic [1:0]  resp
        );
            @(posedge vif.aclk);
            vif.araddr  <= addr;  vif.arprot <= 3'b000;  vif.arvalid <= 1'b1;
            vif.rready  <= 1'b1;

            do @(posedge vif.aclk); while (!vif.arready);
            vif.arvalid <= 1'b0;

            while (!vif.rvalid) @(posedge vif.aclk);
            data = vif.rdata;
            resp = vif.rresp;
            @(posedge vif.aclk);
            vif.rready <= 1'b0;
        endtask

    endclass

endpackage
