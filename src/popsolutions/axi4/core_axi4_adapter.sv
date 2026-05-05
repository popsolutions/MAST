// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Bridge from the upstream RISC-V core's bespoke memory interface
// (core.sv: mem_rd_req / mem_wr_req / mem_addr / mem_rd_data / mem_wr_data
//  / mem_busy / mem_ack) to the AXI4 master request interface exposed by
// axi4_master_simple.
//
// Width mismatch handling:
//   - core operates on 32-bit (xlen / data_width) words
//   - AXI4 transfers 256-bit (mem_data_width) cache lines per beat
//
// Strategy:
//   - Read: issue full cache-line read, then slice the requested 32-bit
//           word out of the 256-bit beat using addr[4:2] as slot index.
//   - Write: replicate the 32-bit datum to all 8 slots of the 256-bit
//            beat and use WSTRB to enable only the 4 bytes of the target
//            slot. No read-modify-write required — AXI4's byte-strobed
//            write semantics handle the partial update at the slave.
//
// Limitations:
//   - 32-bit aligned accesses only. core_mem_addr[1:0] must be 2'b00.
//     Misaligned accesses are treated as if aligned (lower 2 bits ignored).
//   - Single transaction at a time (matches the upstream core's bespoke
//     handshake which has no notion of pipelined memory requests).

`default_nettype none

module core_axi4_adapter (
    input  wire                        clk,
    input  wire                        rst_n,

    // Core-side memory interface (matches upstream conventions)
    input  wire                        core_mem_rd_req,
    input  wire                        core_mem_wr_req,
    input  wire [addr_width-1:0]       core_mem_addr,
    output reg  [data_width-1:0]       core_mem_rd_data,
    input  wire [data_width-1:0]       core_mem_wr_data,
    output reg                         core_mem_busy,
    output reg                         core_mem_ack,

    // AXI4 master request interface (drives axi4_master_simple)
    output reg                         m_req_we,
    output reg  [phys_addr_width-1:0]  m_req_addr,
    output reg  [mem_data_width-1:0]   m_req_wdata,
    output reg  [axi4_strb_width-1:0]  m_req_wstrb,
    output reg                         m_req_start,
    input  wire                        m_req_busy,
    input  wire                        m_req_done,
    input  wire [mem_data_width-1:0]   m_req_rdata,
    input  wire                        m_req_err
);

    localparam [1:0] IDLE = 2'd0,
                     WAIT = 2'd1;

    reg [1:0]              state;
    reg [addr_width-1:0]   addr_q;
    reg                    we_q;

    // The 32-bit slot within the 256-bit cache line is addr[4:2]
    wire [2:0] word_slot = addr_q[4:2];

    // Byte offset of the slot within the cache line (0, 4, 8, ..., 28)
    wire [4:0] byte_offset = {word_slot, 2'b00};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            core_mem_busy    <= 1'b0;
            core_mem_ack     <= 1'b0;
            core_mem_rd_data <= '0;
            addr_q           <= '0;
            we_q             <= 1'b0;

            m_req_we    <= 1'b0;
            m_req_addr  <= '0;
            m_req_wdata <= '0;
            m_req_wstrb <= '0;
            m_req_start <= 1'b0;
        end else begin
            // default: pulses go low
            core_mem_ack <= 1'b0;
            m_req_start  <= 1'b0;

            case (state)
                IDLE: begin
                    if (core_mem_rd_req || core_mem_wr_req) begin
                        addr_q <= core_mem_addr;
                        we_q   <= core_mem_wr_req;

                        // Extend core address (32-bit) to AXI4 address
                        // (phys_addr_width). Cache-line aligned: zero out [4:0].
                        m_req_addr <= {{(phys_addr_width - addr_width){1'b0}},
                                       core_mem_addr[addr_width-1:5], 5'b0};
                        m_req_we   <= core_mem_wr_req;

                        if (core_mem_wr_req) begin
                            // Replicate the 32-bit datum across all 8 slots of
                            // the 256-bit cache line; WSTRB selects which slot
                            // actually lands in the slave's storage.
                            m_req_wdata <= {8{core_mem_wr_data}};
                            // 4 bytes of strobe shifted to the slot's byte offset
                            m_req_wstrb <= {{(axi4_strb_width-4){1'b0}}, 4'hF}
                                           << {core_mem_addr[4:2], 2'b00};
                        end

                        m_req_start   <= 1'b1;
                        core_mem_busy <= 1'b1;
                        state         <= WAIT;
                    end
                end

                WAIT: begin
                    if (m_req_done) begin
                        if (!we_q) begin
                            // Slice the 32-bit word out of the 256-bit response
                            core_mem_rd_data <= m_req_rdata[byte_offset*8 +: data_width];
                        end
                        core_mem_busy <= 1'b0;
                        core_mem_ack  <= 1'b1;
                        state         <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
