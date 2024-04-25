// `timescale 1ns / 1ns

// // registers are 32 bits in RV32
// `define REG_SIZE 31:0

// // insns are 32 bits in RV32IM
// `define INSN_SIZE 31:0

// // RV opcodes are 7 bits
// `define OPCODE_SIZE 6:0

// `ifndef RISCV_FORMAL
// `include "../hw2b/cla.sv"
// `include "../hw3-singlecycle/RvDisassembler.sv"
// `include "../hw4-multicycle/divider_unsigned_pipelined.sv"
// `endif

// module Disasm #(
//     byte PREFIX = "D"
// ) (
//     input wire [31:0] insn,
//     output wire [(8*32)-1:0] disasm
// );
//   // synthesis translate_off
//   // this code is only for simulation, not synthesis
//   string disasm_string;
//   always_comb begin
//     disasm_string = rv_disasm(insn);
//   end
//   // HACK: get disasm_string to appear in GtkWave, which can apparently show only wire/logic. Also,
//   // string needs to be reversed to render correctly.
//   genvar i;
//   for (i = 3; i < 32; i = i + 1) begin : gen_disasm
//     assign disasm[((i+1-3)*8)-1-:8] = disasm_string[31-i];
//   end
//   assign disasm[255-:8] = PREFIX;
//   assign disasm[247-:8] = ":";
//   assign disasm[239-:8] = " ";
//   // synthesis translate_on
// endmodule

// module RegFile (
//     input logic [4:0] rd,
//     input logic [`REG_SIZE] rd_data,
//     input logic [4:0] rs1,
//     output logic [`REG_SIZE] rs1_data,
//     input logic [4:0] rs2,
//     output logic [`REG_SIZE] rs2_data,

//     input logic clk,
//     input logic we,
//     input logic rst
// );
//   localparam int NumRegs = 32;
//   genvar i;
//   logic [`REG_SIZE] regs[NumRegs];

//   // TODO: your code here

// endmodule

// /**
//  * This enum is used to classify each cycle as it comes through the Writeback stage, identifying
//  * if a valid insn is present or, if it is a stall cycle instead, the reason for the stall. The
//  * enum values are mutually exclusive: only one should be set for any given cycle. These values
//  * are compared against the trace-*.json files to ensure that the datapath is running with the
//  * correct timing.
//  *
//  * You will need to set these values at various places within your pipeline, and propagate them
//  * through the stages until they reach Writeback where they can be checked.
//  */
// typedef enum {
//   /** invalid value, this should never appear after the initial reset sequence completes */
//   CYCLE_INVALID = 0,
//   /** a stall cycle that arose from the initial reset signal */
//   CYCLE_RESET = 1,
//   /** not a stall cycle, a valid insn is in Writeback */
//   CYCLE_NO_STALL = 2,
//   /** a stall cycle that arose from a taken branch/jump */
//   CYCLE_TAKEN_BRANCH = 4,

//   // the values below are only needed in HW5B

//   /** a stall cycle that arose from a load-to-use stall */
//   CYCLE_LOAD2USE = 8,
//   /** a stall cycle that arose from a div/rem-to-use stall */
//   CYCLE_DIV2USE = 16,
//   /** a stall cycle that arose from a fence.i insn */
//   CYCLE_FENCEI = 32
// } cycle_status_e;

// /** state at the start of Decode stage */
// typedef struct packed {
//   logic [`REG_SIZE] pc;
//   logic [`INSN_SIZE] insn;
//   cycle_status_e cycle_status;
// } stage_decode_t;


// module DatapathPipelined (
//     input wire clk,
//     input wire rst,
//     output logic [`REG_SIZE] pc_to_imem,
//     input wire [`INSN_SIZE] insn_from_imem,
//     // dmem is read/write
//     output logic [`REG_SIZE] addr_to_dmem,
//     input wire [`REG_SIZE] load_data_from_dmem,
//     output logic [`REG_SIZE] store_data_to_dmem,
//     output logic [3:0] store_we_to_dmem,

//     output logic halt,

//     // The PC of the insn currently in Writeback. 0 if not a valid insn.
//     output logic [`REG_SIZE] trace_writeback_pc,
//     // The bits of the insn currently in Writeback. 0 if not a valid insn.
//     output logic [`INSN_SIZE] trace_writeback_insn,
//     // The status of the insn (or stall) currently in Writeback. See cycle_status_e enum for valid values.
//     output cycle_status_e trace_writeback_cycle_status
// );

//   // opcodes - see section 19 of RiscV spec
//   localparam bit [`OPCODE_SIZE] OpcodeLoad = 7'b00_000_11;
//   localparam bit [`OPCODE_SIZE] OpcodeStore = 7'b01_000_11;
//   localparam bit [`OPCODE_SIZE] OpcodeBranch = 7'b11_000_11;
//   localparam bit [`OPCODE_SIZE] OpcodeJalr = 7'b11_001_11;
//   localparam bit [`OPCODE_SIZE] OpcodeMiscMem = 7'b00_011_11;
//   localparam bit [`OPCODE_SIZE] OpcodeJal = 7'b11_011_11;

//   localparam bit [`OPCODE_SIZE] OpcodeRegImm = 7'b00_100_11;
//   localparam bit [`OPCODE_SIZE] OpcodeRegReg = 7'b01_100_11;
//   localparam bit [`OPCODE_SIZE] OpcodeEnviron = 7'b11_100_11;

//   localparam bit [`OPCODE_SIZE] OpcodeAuipc = 7'b00_101_11;
//   localparam bit [`OPCODE_SIZE] OpcodeLui = 7'b01_101_11;

//   // cycle counter, not really part of any stage but useful for orienting within GtkWave
//   // do not rename this as the testbench uses this value
//   logic [`REG_SIZE] cycles_current;
//   always_ff @(posedge clk) begin
//     if (rst) begin
//       cycles_current <= 0;
//     end else begin
//       cycles_current <= cycles_current + 1;
//     end
//   end

//   /***************/
//   /* FETCH STAGE */
//   /***************/

//   logic [`REG_SIZE] f_pc_current;
//   wire [`REG_SIZE] f_insn;
//   cycle_status_e f_cycle_status;

//   // program counter
//   always_ff @(posedge clk) begin
//     if (rst) begin
//       f_pc_current <= 32'd0;
//       // NB: use CYCLE_NO_STALL since this is the value that will persist after the last reset cycle
//       f_cycle_status <= CYCLE_NO_STALL;
//     end else begin
//       f_cycle_status <= CYCLE_NO_STALL;
//       f_pc_current <= f_pc_current + 4;
//     end
//   end
//   // send PC to imem
//   assign pc_to_imem = f_pc_current;
//   assign f_insn = insn_from_imem;

//   // Here's how to disassemble an insn into a string you can view in GtkWave.
//   // Use PREFIX to provide a 1-character tag to identify which stage the insn comes from.
//   wire [255:0] f_disasm;
//   Disasm #(
//       .PREFIX("F")
//   ) disasm_0fetch (
//       .insn  (f_insn),
//       .disasm(f_disasm)
//   );

//   /****************/
//   /* DECODE STAGE */
//   /****************/

//   // this shows how to package up state in a `struct packed`, and how to pass it between stages
//   stage_decode_t decode_state;
//   always_ff @(posedge clk) begin
//     if (rst) begin
//       decode_state <= '{
//         pc: 0,
//         insn: 0,
//         cycle_status: CYCLE_RESET
//       };
//     end else begin
//       begin
//         decode_state <= '{
//           pc: f_pc_current,
//           insn: f_insn,
//           cycle_status: f_cycle_status
//         };
//       end
//     end
//   end
//   wire [255:0] d_disasm;
//   Disasm #(
//       .PREFIX("D")
//   ) disasm_1decode (
//       .insn  (decode_state.insn),
//       .disasm(d_disasm)
//   );

//   // TODO: your code here, though you will also need to modify some of the code above
//   // TODO: the testbench requires that your register file instance is named `rf`

// endmodule

// module MemorySingleCycle #(
//     parameter int NUM_WORDS = 512
// ) (
//     // rst for both imem and dmem
//     input wire rst,

//     // clock for both imem and dmem. The memory reads/writes on @(negedge clk)
//     input wire clk,

//     // must always be aligned to a 4B boundary
//     input wire [`REG_SIZE] pc_to_imem,

//     // the value at memory location pc_to_imem
//     output logic [`REG_SIZE] insn_from_imem,

//     // must always be aligned to a 4B boundary
//     input wire [`REG_SIZE] addr_to_dmem,

//     // the value at memory location addr_to_dmem
//     output logic [`REG_SIZE] load_data_from_dmem,

//     // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
//     input wire [`REG_SIZE] store_data_to_dmem,

//     // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
//     // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
//     input wire [3:0] store_we_to_dmem
// );

//   // memory is arranged as an array of 4B words
//   logic [`REG_SIZE] mem[NUM_WORDS];

//   initial begin
//     $readmemh("mem_initial_contents.hex", mem, 0);
//   end

//   always_comb begin
//     // memory addresses should always be 4B-aligned
//     assert (pc_to_imem[1:0] == 2'b00);
//     assert (addr_to_dmem[1:0] == 2'b00);
//   end

//   localparam int AddrMsb = $clog2(NUM_WORDS) + 1;
//   localparam int AddrLsb = 2;

//   always @(negedge clk) begin
//     if (rst) begin
//     end else begin
//       insn_from_imem <= mem[{pc_to_imem[AddrMsb:AddrLsb]}];
//     end
//   end

//   always @(negedge clk) begin
//     if (rst) begin
//     end else begin
//       if (store_we_to_dmem[0]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
//       end
//       if (store_we_to_dmem[1]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
//       end
//       if (store_we_to_dmem[2]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
//       end
//       if (store_we_to_dmem[3]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
//       end
//       // dmem is "read-first": read returns value before the write
//       load_data_from_dmem <= mem[{addr_to_dmem[AddrMsb:AddrLsb]}];
//     end
//   end
// endmodule

// /* This design has just one clock for both processor and memory. */
// module RiscvProcessor (
//     input  wire  clk,
//     input  wire  rst,
//     output logic halt,
//     output wire [`REG_SIZE] trace_writeback_pc,
//     output wire [`INSN_SIZE] trace_writeback_insn,
//     output cycle_status_e trace_writeback_cycle_status
// );

//   wire [`INSN_SIZE] insn_from_imem;
//   wire [`REG_SIZE] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
//   wire [3:0] mem_data_we;

//   MemorySingleCycle #(
//       .NUM_WORDS(8192)
//   ) the_mem (
//       .rst                (rst),
//       .clk                (clk),
//       // imem is read-only
//       .pc_to_imem         (pc_to_imem),
//       .insn_from_imem     (insn_from_imem),
//       // dmem is read-write
//       .addr_to_dmem       (mem_data_addr),
//       .load_data_from_dmem(mem_data_loaded_value),
//       .store_data_to_dmem (mem_data_to_write),
//       .store_we_to_dmem   (mem_data_we)
//   );

//   DatapathPipelined datapath (
//       .clk(clk),
//       .rst(rst),
//       .pc_to_imem(pc_to_imem),
//       .insn_from_imem(insn_from_imem),
//       .addr_to_dmem(mem_data_addr),
//       .store_data_to_dmem(mem_data_to_write),
//       .store_we_to_dmem(mem_data_we),
//       .load_data_from_dmem(mem_data_loaded_value),
//       .halt(halt),
//       .trace_writeback_pc(trace_writeback_pc),
//       .trace_writeback_insn(trace_writeback_insn),
//       .trace_writeback_cycle_status(trace_writeback_cycle_status)
//   );

// endmodule


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// `timescale 1ns / 1ns

// // registers are 32 bits in RV32
// `define REG_SIZE 31:0

// // insns are 32 bits in RV32IM
// `define INSN_SIZE 31:0

// // RV opcodes are 7 bits
// `define OPCODE_SIZE 6:0

// `ifndef RISCV_FORMAL
// `include "../hw2b/cla.sv"
// `include "../hw3-singlecycle/RvDisassembler.sv"
// `include "../hw4-multicycle/divider_unsigned_pipelined.sv"
// `endif

// module Disasm #(
//     byte PREFIX = "D"
// ) (
//     input wire [31:0] insn,
//     output wire [(8*32)-1:0] disasm
// );
//   // synthesis translate_off
//   // this code is only for simulation, not synthesis
//   string disasm_string;
//   always_comb begin
//     disasm_string = rv_disasm(insn);
//   end
//   // HACK: get disasm_string to appear in GtkWave, which can apparently show only wire/logic. Also,
//   // string needs to be reversed to render correctly.
//   genvar i;
//   for (i = 3; i < 32; i = i + 1) begin : gen_disasm
//     assign disasm[((i+1-3)*8)-1-:8] = disasm_string[31-i];
//   end
//   assign disasm[255-:8] = PREFIX;
//   assign disasm[247-:8] = ":";
//   assign disasm[239-:8] = " ";
//   // synthesis translate_on
// endmodule

// module RegFile (
//     input logic [4:0] rd,
//     input logic [`REG_SIZE] rd_data,
//     input logic [4:0] rs1,
//     output logic [`REG_SIZE] rs1_data,
//     input logic [4:0] rs2,
//     output logic [`REG_SIZE] rs2_data,

//     input logic clk,
//     input logic we,
//     input logic rst
// );

// // TODO: copy your HW3B code here
// localparam int NumRegs = 32;
// logic [`REG_SIZE] regs[NumRegs];

// // TODO: your code here
// assign regs[0] = 'h0;           //addr 0 set to 0
// assign rs1_data = regs[rs1];    //rd data1
// assign rs2_data = regs[rs2];    //rd data2

// integer i;

// //wr data
// always_ff @(posedge clk)
// if (rst) begin
//   for (i = 1; i < NumRegs; i = i + 1) begin
//     regs[i] <= 'h0;
//   end
// end else if (we && (|rd)) begin   //we high and not write to 0 address
//   regs[rd] <= rd_data;
// end

// endmodule

// /**
//  * This enum is used to classify each cycle as it comes through the Writeback stage, identifying
//  * if a valid insn is present or, if it is a stall cycle instead, the reason for the stall. The
//  * enum values are mutually exclusive: only one should be set for any given cycle. These values
//  * are compared against the trace-*.json files to ensure that the datapath is running with the
//  * correct timing.
//  *
//  * You will need to set these values at various places within your pipeline, and propagate them
//  * through the stages until they reach Writeback where they can be checked.
//  */
// typedef enum {
//   /** invalid value, this should never appear after the initial reset sequence completes */
//   CYCLE_INVALID = 0,
//   /** a stall cycle that arose from the initial reset signal */
//   CYCLE_RESET = 1,
//   /** not a stall cycle, a valid insn is in Writeback */
//   CYCLE_NO_STALL = 2,
//   /** a stall cycle that arose from a taken branch/jump */
//   CYCLE_TAKEN_BRANCH = 4,

//   // the values below are only needed in HW5B

//   /** a stall cycle that arose from a load-to-use stall */
//   CYCLE_LOAD2USE = 8,
//   /** a stall cycle that arose from a div/rem-to-use stall */
//   CYCLE_DIV2USE = 16,
//   /** a stall cycle that arose from a fence.i insn */
//   CYCLE_FENCEI = 32
// } cycle_status_e;

// module DatapathPipelined (
//     input wire clk,
//     input wire rst,
//     output logic [`REG_SIZE] pc_to_imem,
//     input wire [`INSN_SIZE] insn_from_imem,
//     // dmem is read/write
//     output logic [`REG_SIZE] addr_to_dmem,
//     input wire [`REG_SIZE] load_data_from_dmem,
//     output logic [`REG_SIZE] store_data_to_dmem,
//     output logic [3:0] store_we_to_dmem,

//     output logic halt,

//     // The PC of the insn currently in Writeback. 0 if not a valid insn.
//     output logic [`REG_SIZE] trace_writeback_pc,
//     // The bits of the insn currently in Writeback. 0 if not a valid insn.
//     output logic [`INSN_SIZE] trace_writeback_insn,
//     // The status of the insn (or stall) currently in Writeback. See cycle_status_e enum for valid values.
//     output cycle_status_e trace_writeback_cycle_status
// );

//   // opcodes - see section 19 of RiscV spec
//   localparam bit [`OPCODE_SIZE] OpLoad = 7'b00_000_11;
//   localparam bit [`OPCODE_SIZE] OpStore = 7'b01_000_11;
//   localparam bit [`OPCODE_SIZE] OpBranch = 7'b11_000_11;
//   localparam bit [`OPCODE_SIZE] OpJalr = 7'b11_001_11;
//   localparam bit [`OPCODE_SIZE] OpMiscMem = 7'b00_011_11;
//   localparam bit [`OPCODE_SIZE] OpJal = 7'b11_011_11;

//   localparam bit [`OPCODE_SIZE] OpRegImm = 7'b00_100_11;
//   localparam bit [`OPCODE_SIZE] OpRegReg = 7'b01_100_11;
//   localparam bit [`OPCODE_SIZE] OpEnviron = 7'b11_100_11;

//   localparam bit [`OPCODE_SIZE] OpAuipc = 7'b00_101_11;
//   localparam bit [`OPCODE_SIZE] OpLui = 7'b01_101_11;

//   // cycle counter, not really part of any stage but useful for orienting within GtkWave
//   // do not rename this as the testbench uses this value
//   logic [`REG_SIZE] cycles_current;
//   always_ff @(posedge clk) begin
//     if (rst) begin
//       cycles_current <= 0;
//     end else begin
//       cycles_current <= cycles_current + 1;
//     end
//   end

//   /************************************************************************/
//   /* Define components out of pipeline & data communication between stages*/
//   /************************************************************************/
//   logic [31:0] pc_next;
//   logic branch_taken;     //obtained at EXECUTE stage
//   //used in rf (because rf is instantiated in the DECODE stage, these two definitions should be advanced)
//   logic [4:0] w_insn_rd;
//   wire [4:0] m_insn_rd;

//   /*************************************/
//   /*     Propagation between stages    */
//   /*************************************/
//   //--- -> Fetch stage:
//   logic [`REG_SIZE] f_pc_current;
//   wire [`REG_SIZE] f_insn;
//   cycle_status_e f_cycle_status;

//   //--- F -> D:
//   logic [`REG_SIZE] d_pc;
//   logic [`INSN_SIZE] d_insn;
//   cycle_status_e d_cycle_status;

//   //--- D -> X:
//   logic [`REG_SIZE] x_pc;
//   logic [`REG_SIZE] x_rs1_data;
//   logic [`REG_SIZE] x_rs2_data;
//   logic [46:0] x_sub_insn;
//   logic [`INSN_SIZE] x_insn;
//   cycle_status_e x_cycle_status;

//   //--- X -> M:
//   logic [`REG_SIZE] m_pc;
//   logic [`REG_SIZE] m_rd_data;
//   logic m_we;
//   logic [`REG_SIZE] m_addr_mem;
//   logic [`REG_SIZE] m_store_data_to_dmem;
//   logic [3:0] m_store_we_to_dmem;
//   logic [7:0] m_sub_insn;
//   logic [`INSN_SIZE] m_insn;
//   logic m_illegal_insn;
//   logic m_halt;
//   cycle_status_e m_cycle_status;

//   //--- M -> W:
//   logic [`REG_SIZE] w_pc;
//   logic [`REG_SIZE] w_rd_data;
//   logic w_we;
//   logic [`INSN_SIZE] w_insn;
//   logic [4:0] w_sub_insn;
//   logic w_illegal_insn;
//   logic w_halt;
//   cycle_status_e w_cycle_status;

//   /*************************************************************************************************/
//   /*                                         FETCH STAGE                                           */
//   /*************************************************************************************************/
//   // program counter
//   always_ff @(posedge clk) begin
//     if (rst) begin
//       f_pc_current <= 32'd0;
//       // NB: use CYCLE_NO_STALL since this is the value that will persist after the last reset cycle
//       f_cycle_status <= CYCLE_NO_STALL;
//     end else begin
//       f_cycle_status <= CYCLE_NO_STALL;
//       f_pc_current <= pc_next;
//     end
//   end
//   // send PC to imem
//   assign pc_to_imem = f_pc_current;
//   assign f_insn = insn_from_imem;

//   // Here's how to disassemble an insn into a string you can view in GtkWave.
//   // Use PREFIX to provide a 1-character tag to identify which stage the insn comes from.
//   wire [(8*32)-1:0] f_disasm;
//   Disasm #(
//       .PREFIX("F")
//   ) disasm_0fetch (
//       .insn  (f_insn),
//       .disasm(f_disasm)
//   );

//   /*************************************************************************************************/
//   /*                                         DECODE STAGE                                          */
//   /*************************************************************************************************/
  
//   //propagation from last stage
//   always_ff @(posedge clk) begin
//     if (rst) begin
//       d_pc <= 'd0;
//       d_insn <= 'd0;
//       d_cycle_status <= CYCLE_RESET;
//     end else if (!branch_taken) begin
//       d_pc <= f_pc_current;
//       d_insn <= f_insn;
//       d_cycle_status <= f_cycle_status;
//     end else begin
//       d_pc <= 'd0;
//       d_insn <= 'd0;
//       d_cycle_status <= CYCLE_TAKEN_BRANCH;
//     end
//   end

//   //R-type instruction
//   wire [6:0] d_insn_funct7;
//   wire [4:0] d_insn_rs2;
//   wire [4:0] d_insn_rs1;
//   wire [2:0] d_insn_funct3;
//   wire [4:0] d_insn_rd;
//   wire [`OPCODE_SIZE] d_insn_opcode;

//   // split R-type instruction - see section 2.2 of RiscV spec
//   assign {d_insn_funct7, d_insn_rs2, d_insn_rs1, d_insn_funct3, d_insn_rd, d_insn_opcode} = d_insn;

//   //imm values for all types of insn
//   wire [11:0] d_imm_i;
//   wire [11:0] d_imm_s;
//   wire [12:0] d_imm_b;
//   wire [20:0] d_imm_j;
//   wire [19:0] d_imm_u;

//   assign d_imm_i = d_insn[31:20];
//   assign d_imm_s[11:5] = d_insn_funct7, d_imm_s[4:0] = d_insn_rd;
//   assign {d_imm_b[12], d_imm_b[10:5]} = d_insn_funct7, {d_imm_b[4:1], d_imm_b[11]} = d_insn_rd, d_imm_b[0] = 1'b0;
//   assign {d_imm_j[20], d_imm_j[10:1], d_imm_j[11], d_imm_j[19:12], d_imm_j[0]} = {d_insn[31:12], 1'b0};
//   assign d_imm_u = d_insn[31:12];

//   //--- insn's sub-insn decode
//   wire d_insn_lui = d_insn_opcode == OpLui;
//   wire d_insn_auipc = d_insn_opcode == OpAuipc;
//   wire d_insn_jal = d_insn_opcode == OpJal;
//   wire d_insn_jalr = d_insn_opcode == OpJalr;
  
//   wire d_insn_beq = d_insn_opcode == OpBranch && d_insn[14:12] == 3'b000;
//   wire d_insn_bne = d_insn_opcode == OpBranch && d_insn[14:12] == 3'b001;
//   wire d_insn_blt = d_insn_opcode == OpBranch && d_insn[14:12] == 3'b100;
//   wire d_insn_bge = d_insn_opcode == OpBranch && d_insn[14:12] == 3'b101;
//   wire d_insn_bltu = d_insn_opcode == OpBranch && d_insn[14:12] == 3'b110;
//   wire d_insn_bgeu = d_insn_opcode == OpBranch && d_insn[14:12] == 3'b111;
  
//   wire d_insn_lb = d_insn_opcode == OpLoad && d_insn[14:12] == 3'b000;
//   wire d_insn_lh = d_insn_opcode == OpLoad && d_insn[14:12] == 3'b001;
//   wire d_insn_lw = d_insn_opcode == OpLoad && d_insn[14:12] == 3'b010;
//   wire d_insn_lbu = d_insn_opcode == OpLoad && d_insn[14:12] == 3'b100;
//   wire d_insn_lhu = d_insn_opcode == OpLoad && d_insn[14:12] == 3'b101;
  
//   wire d_insn_sb = d_insn_opcode == OpStore && d_insn[14:12] == 3'b000;
//   wire d_insn_sh = d_insn_opcode == OpStore && d_insn[14:12] == 3'b001;
//   wire d_insn_sw = d_insn_opcode == OpStore && d_insn[14:12] == 3'b010;
  
//   wire d_insn_addi = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b000;
//   wire d_insn_slti = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b010;
//   wire d_insn_sltiu = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b011;
//   wire d_insn_xori = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b100;
//   wire d_insn_ori = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b110;
//   wire d_insn_andi = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b111;
  
//   wire d_insn_slli = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b001 && d_insn[31:25] == 7'd0;
//   wire d_insn_srli = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b101 && d_insn[31:25] == 7'd0;
//   wire d_insn_srai = d_insn_opcode == OpRegImm && d_insn[14:12] == 3'b101 && d_insn[31:25] == 7'b0100000;
  
//   wire d_insn_add = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b000 && d_insn[31:25] == 7'd0;
//   wire d_insn_sub  = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b000 && d_insn[31:25] == 7'b0100000;
//   wire d_insn_sll = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b001 && d_insn[31:25] == 7'd0;
//   wire d_insn_slt = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b010 && d_insn[31:25] == 7'd0;
//   wire d_insn_sltu = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b011 && d_insn[31:25] == 7'd0;
//   wire d_insn_xor = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b100 && d_insn[31:25] == 7'd0;
//   wire d_insn_srl = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b101 && d_insn[31:25] == 7'd0;
//   wire d_insn_sra  = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b101 && d_insn[31:25] == 7'b0100000;
//   wire d_insn_or = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b110 && d_insn[31:25] == 7'd0;
//   wire d_insn_and = d_insn_opcode == OpRegReg && d_insn[14:12] == 3'b111 && d_insn[31:25] == 7'd0;
  
//   wire d_insn_mul    = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b000;
//   wire d_insn_mulh   = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b001;
//   wire d_insn_mulhsu = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b010;
//   wire d_insn_mulhu  = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b011;
//   wire d_insn_div    = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b100;
//   wire d_insn_divu   = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b101;
//   wire d_insn_rem    = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b110;
//   wire d_insn_remu   = d_insn_opcode == OpRegReg && d_insn[31:25] == 7'd1 && d_insn[14:12] == 3'b111;
  
//   wire d_insn_ecall = d_insn_opcode == OpEnviron && d_insn[31:7] == 25'd0;
//   wire d_insn_fence = d_insn_opcode == OpMiscMem;

//   //index for d_sub_insn, e.g: d_sub_insn[46] == d_sub_insn[insn_lui] == d_insn_lui
//   localparam [5:0] insn_lui='d46, insn_auipc='d45, insn_jal='d44, insn_jalr='d43, insn_beq='d42, insn_bne='d41, insn_blt='d40, insn_bge='d39, insn_bltu='d38, insn_bgeu='d37, 
//   insn_lb='d36, insn_lh='d35, insn_lw='d34, insn_lbu='d33, insn_lhu='d32, insn_sb='d31, insn_sh='d30, insn_sw='d29, insn_addi='d28, insn_slti='d27, insn_sltiu='d26,
//   insn_xori='d25, insn_ori='d24, insn_andi='d23, insn_slli='d22, insn_srli='d21, insn_srai='d20, insn_add='d19, insn_sub='d18, insn_sll='d17, insn_slt='d16, insn_sltu='d15, 
//   insn_xor='d14, insn_srl='d13, insn_sra='d12, insn_or='d11, insn_and='d10, insn_mul='d9, insn_mulh='d8, insn_mulhsu='d7, insn_mulhu='d6, insn_div='d5, insn_divu='d4,
//   insn_rem='d3, insn_remu='d2, insn_ecall='d1, insn_fence='d0;

//   //for propagated to EXECUTE stage
//   wire [46:0] d_sub_insn = {d_insn_lui, d_insn_auipc, d_insn_jal, d_insn_jalr, d_insn_beq, d_insn_bne, d_insn_blt, d_insn_bge, d_insn_bltu, d_insn_bgeu,
//             d_insn_lb, d_insn_lh, d_insn_lw, d_insn_lbu, d_insn_lhu, d_insn_sb, d_insn_sh, d_insn_sw, d_insn_addi, d_insn_slti, d_insn_sltiu,
//             d_insn_xori, d_insn_ori, d_insn_andi, d_insn_slli, d_insn_srli, d_insn_srai, d_insn_add, d_insn_sub, d_insn_sll, d_insn_slt, d_insn_sltu, 
//             d_insn_xor, d_insn_srl, d_insn_sra, d_insn_or, d_insn_and, d_insn_mul, d_insn_mulh, d_insn_mulhsu, d_insn_mulhu, d_insn_div, d_insn_divu, 
//             d_insn_rem, d_insn_remu, d_insn_ecall, d_insn_fence};

//   //--- WD bypass:
//   wire d_bypass_WD;
//   logic [31:0] d_rs1_data_bp, d_rs2_data_bp;      //bypass mux for rs1_data, rs2_data
//   wire d_rs1_dependency, d_rs2_dependency;        //rs1 and rs2 dependency between WD
//   //reg file inf
//   wire [31:0] d_rs1_data_rf;
//   wire [31:0] d_rs2_data_rf;

//   assign d_rs1_dependency = (d_insn_rs1 == w_insn_rd);
//   assign d_rs2_dependency = (d_insn_rs2 == w_insn_rd);
//   assign d_bypass_WD = (d_rs1_dependency | d_rs2_dependency) && w_we && (|w_insn_rd);    //W stage is wr to rf & not wr to x0

//   always_comb begin
//     d_rs1_data_bp = d_rs1_data_rf;
//     d_rs2_data_bp = d_rs2_data_rf;

//     if (d_bypass_WD & d_rs1_dependency)      //WD & rs1 dependency
//       d_rs1_data_bp = w_rd_data;
//     if (d_bypass_WD & d_rs2_dependency)      //WD & rs2 dependency
//       d_rs2_data_bp = w_rd_data;
//   end
  
//   //register file
//   RegFile rf(
//     .rd       (  w_insn_rd  ),      //wr in write-back stage
//     .rd_data  (  w_rd_data  ),
//     .rs1      (  d_insn_rs1 ),      //rd in decode stage
//     .rs1_data (  d_rs1_data_rf ),
//     .rs2      (  d_insn_rs2 ),
//     .rs2_data (  d_rs2_data_rf ),

//     .clk      (  clk      ),
//     .we       (  w_we       ),
//     .rst      (  rst      )
//   );

//   wire [(8*32)-1:0] d_disasm;
//   Disasm #(
//       .PREFIX("D")
//   ) disasm_1decode (
//       .insn   (d_insn),
//       .disasm (d_disasm)
//   );

//   // TODO: your code here, though you will also need to modify some of the code above
//   // TODO: the testbench requires that your register file instance is named `rf`

//   /*************************************************************************************************/
//   /*                                         EXECUTE STAGE                                         */
//   /*************************************************************************************************/
 

//   /*************************************************************************************************/
//   /*                                         MEMORY STAGE                                          */
//   /*************************************************************************************************/

//   //propagated from last stage
//   always_ff @(posedge clk)
//   if (rst) begin
//     m_pc <= 'd0;
//     m_rd_data <= 'd0;
//     m_we <= 1'b0;
//     m_addr_mem <= 'd0;
//     m_store_data_to_dmem <= 'd0;
//     m_store_we_to_dmem <= 4'b0000;
//     m_sub_insn <= 'd0;
//     m_insn <= 'd0;
//     m_illegal_insn <= 1'b0;
//     m_halt <= 1'b0;
//     m_cycle_status <= CYCLE_RESET;
//   end else if (!x_illegal_insn) begin
//     m_pc <= x_pc;
//     m_rd_data <= x_rd_data;
//     m_we <= x_we;
//     m_addr_mem <= x_addr_mem;
//     m_store_data_to_dmem <= x_store_data_to_dmem;
//     m_store_we_to_dmem <= x_store_we_to_dmem;
//     m_sub_insn <= x_sub_insn[36:29];                  //only store and load insn need to be propagated to save registers
//     m_insn <= x_insn;
//     m_illegal_insn <= x_illegal_insn;
//     m_halt <= x_halt;
//     m_cycle_status <= x_cycle_status;
//   end else begin
//     m_pc <= 'd0;
//     m_rd_data <= 'd0;
//     m_we <= 1'b0;
//     m_addr_mem <= 'd0;
//     m_store_data_to_dmem <= 'd0;
//     m_store_we_to_dmem <= 4'b0000;
//     m_sub_insn <= 'd0;
//     m_insn <= 'd0;
//     m_illegal_insn <= x_illegal_insn;
//     m_halt <= 1'b0;
//     m_cycle_status <= CYCLE_INVALID;
//   end

//   //index for m_sub_insn, only has load and store insn
//   parameter [2:0] m_insn_lb='d7, m_insn_lh='d6, m_insn_lw='d5, m_insn_lbu='d4, m_insn_lhu='d3, m_insn_sb='d2, m_insn_sh='d1, m_insn_sw='d0;

//   //decode at this stage
//   wire [6:0] m_insn_funct7;
//   wire [4:0] m_insn_rs2;
//   wire [4:0] m_insn_rs1;
//   wire [2:0] m_insn_funct3;
//   wire [`OPCODE_SIZE] m_insn_opcode;

//   assign {m_insn_funct7, m_insn_rs2, m_insn_rs1, m_insn_funct3, m_insn_rd, m_insn_opcode} = m_insn;

//   //--- WM bypass:
//   logic m_bypass_WM;
//   logic [31:0] m_store_data_to_dmem_bp;     //only bypass the store data to mem
//   wire m_rs2_dependency;                    //only need to check rs2 dependency for st rs2, imm12(rs1) -> ld rd, imm12(rs1) 
//   wire m_isStore, w_isLoad;              

//   assign m_rs2_dependency = (m_insn_rs2 == w_insn_rd);
//   assign m_isStore = |m_sub_insn[m_insn_sb: m_insn_sw];   //one of load & store sub-insn is 1
//   assign w_isLoad = |w_sub_insn;
//   assign m_bypass_WM = m_rs2_dependency && m_isStore && w_isLoad && (|w_insn_rd);   //rs2 dependency & M: store & W: load & not load to x0

//   assign m_store_data_to_dmem_bp = (m_bypass_WM)? w_rd_data : m_store_data_to_dmem;

//   logic [31:0] m_load_data_from_dmem;

//   wire [(8*32)-1:0] m_disasm;
//   Disasm #(
//       .PREFIX("M")
//   ) disasm_3fetch (
//       .insn  (m_insn),
//       .disasm(m_disasm)
//   );


//   /*************************************************************************************************/
//   /*                                         WRITE-BACK STAGE                                      */
//   /*************************************************************************************************/

//   //propagated from last stage
//   always_ff @(posedge clk)
//   if (rst) begin
//     w_pc <= 'd0;
//     w_rd_data <= 'd0;
//     w_we <= 1'b0;
//     w_insn <= 'd0;
//     w_sub_insn <= 'd0;
//     w_illegal_insn <= 1'b0;
//     w_halt <= 1'b0;
//     w_cycle_status <= CYCLE_RESET;
//   end else if (!m_illegal_insn) begin
//     w_pc <= m_pc;
//     w_rd_data <= m_rd_data;
//     w_we <= m_we;
//     w_insn <= m_insn;
//     w_sub_insn <= m_sub_insn[m_insn_lb: m_insn_lhu];      //only need to propagated load insn to save registers
//     w_illegal_insn <= m_illegal_insn;
//     w_halt <= m_halt;
//     w_cycle_status <= m_cycle_status;
//   end else begin
//     w_pc <= 'd0;
//     w_rd_data <= 'd0;
//     w_we <= 1'b0;
//     w_insn <= 'd0;
//     w_sub_insn <= 'd0;
//     w_illegal_insn <= m_illegal_insn;
//     w_halt <= 1'b0;
//     w_cycle_status <= CYCLE_INVALID;
//   end

//   //decode at this stage
//   wire [6:0] w_insn_funct7;
//   wire [4:0] w_insn_rs2;
//   wire [4:0] w_insn_rs1;
//   wire [2:0] w_insn_funct3;
//   wire [`OPCODE_SIZE] w_insn_opcode;

//   assign {w_insn_funct7, w_insn_rs2, w_insn_rs1, w_insn_funct3, w_insn_rd, w_insn_opcode} = w_insn;   //for WM bypass
//   assign halt = w_halt;

//   //test signals
//   assign trace_writeback_pc = (!w_illegal_insn)? w_pc : 'd0;
//   assign trace_writeback_insn = (!w_illegal_insn)? w_insn : 'd0;
//   assign trace_writeback_cycle_status = w_cycle_status;


//   wire [(8*32)-1:0] w_disasm;
//   Disasm #(
//       .PREFIX("W")
//   ) disasm_4fetch (
//       .insn  (w_insn),
//       .disasm(w_disasm)
//   );

// endmodule

// module MemorySingleCycle #(
//     parameter int NUM_WORDS = 512
// ) (
//     // rst for both imem and dmem
//     input wire rst,

//     // clock for both imem and dmem. The memory reads/writes on @(negedge clk)
//     input wire clk,

//     // must always be aligned to a 4B boundary
//     input wire [`REG_SIZE] pc_to_imem,

//     // the value at memory location pc_to_imem
//     output logic [`REG_SIZE] insn_from_imem,

//     // must always be aligned to a 4B boundary
//     input wire [`REG_SIZE] addr_to_dmem,

//     // the value at memory location addr_to_dmem
//     output logic [`REG_SIZE] load_data_from_dmem,

//     // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
//     input wire [`REG_SIZE] store_data_to_dmem,

//     // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
//     // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
//     input wire [3:0] store_we_to_dmem
// );

//   // memory is arranged as an array of 4B words
//   logic [`REG_SIZE] mem[NUM_WORDS];

//   initial begin
//     $readmemh("mem_initial_contents.hex", mem, 0);
//   end

//   always_comb begin
//     // memory addresses should always be 4B-aligned
//     assert (pc_to_imem[1:0] == 2'b00);
//     assert (addr_to_dmem[1:0] == 2'b00);
//   end

//   localparam int AddrMsb = $clog2(NUM_WORDS) + 1;
//   localparam int AddrLsb = 2;

//   always @(negedge clk) begin
//     if (rst) begin
//     end else begin
//       insn_from_imem <= mem[{pc_to_imem[AddrMsb:AddrLsb]}];
//     end
//   end

//   always @(negedge clk) begin
//     if (rst) begin
//     end else begin
//       if (store_we_to_dmem[0]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
//       end
//       if (store_we_to_dmem[1]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
//       end
//       if (store_we_to_dmem[2]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
//       end
//       if (store_we_to_dmem[3]) begin
//         mem[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
//       end
//       // dmem is "read-first": read returns value before the write
//       load_data_from_dmem <= mem[{addr_to_dmem[AddrMsb:AddrLsb]}];
//     end
//   end
// endmodule

// /* This design has just one clock for both processor and memory. */
// module RiscvProcessor (
//     input  wire  clk,
//     input  wire  rst,
//     output logic halt,
//     output wire [`REG_SIZE] trace_writeback_pc,
//     output wire [`INSN_SIZE] trace_writeback_insn,
//     output cycle_status_e trace_writeback_cycle_status
// );

//   wire [`INSN_SIZE] insn_from_imem;
//   wire [`REG_SIZE] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
//   wire [3:0] mem_data_we;

//   MemorySingleCycle #(
//       .NUM_WORDS(8192)
//   ) the_mem (
//       .rst                (rst),
//       .clk                (clk),
//       // imem is read-only
//       .pc_to_imem         (pc_to_imem),
//       .insn_from_imem     (insn_from_imem),
//       // dmem is read-write
//       .addr_to_dmem       (mem_data_addr),
//       .load_data_from_dmem(mem_data_loaded_value),
//       .store_data_to_dmem (mem_data_to_write),
//       .store_we_to_dmem   (mem_data_we)
//   );

//   DatapathPipelined datapath (
//       .clk(clk),
//       .rst(rst),
//       .pc_to_imem(pc_to_imem),
//       .insn_from_imem(insn_from_imem),
//       .addr_to_dmem(mem_data_addr),
//       .store_data_to_dmem(mem_data_to_write),
//       .store_we_to_dmem(mem_data_we),
//       .load_data_from_dmem(mem_data_loaded_value),
//       .halt(halt),
//       .trace_writeback_pc(trace_writeback_pc),
//       .trace_writeback_insn(trace_writeback_insn),
//       .trace_writeback_cycle_status(trace_writeback_cycle_status)
//   );

// endmodule

`timescale 1ns / 1ns

// registers are 32 bits in RV32
`define REG_SIZE 31:0

// insns are 32 bits in RV32IM
`define INSN_SIZE 31:0

// RV opcodes are 7 bits
`define OPCODE_SIZE 6:0

`ifndef RISCV_FORMAL
`include "../hw2b/cla.sv"
`include "../hw3-singlecycle/RvDisassembler.sv"
`include "../hw4-multicycle/divider_unsigned_pipelined.sv"
`endif

module Disasm #(
    byte PREFIX = "D"
) (
    input wire [31:0] insn,
    output wire [(8*32)-1:0] disasm
);
  // synthesis translate_off
  // this code is only for simulation, not synthesis
  string disasm_string;
  always_comb begin
    disasm_string = rv_disasm(insn);
  end
  // HACK: get disasm_string to appear in GtkWave, which can apparently show only wire/logic. Also,
  // string needs to be reversed to render correctly.
  genvar i;
  for (i = 3; i < 32; i = i + 1) begin : gen_disasm
    assign disasm[((i+1-3)*8)-1-:8] = disasm_string[31-i];
  end
  assign disasm[255-:8] = PREFIX;
  assign disasm[247-:8] = ":";
  assign disasm[239-:8] = " ";
  // synthesis translate_on
endmodule

module RegFile (
    input logic [4:0] rd,
    input logic [`REG_SIZE] rd_data,
    input logic [4:0] rs1,
    output logic [`REG_SIZE] rs1_data,
    input logic [4:0] rs2,
    output logic [`REG_SIZE] rs2_data,

    input logic clk,
    input logic we,
    input logic rst
);
  localparam int NumRegs = 32;
  integer i;
  logic [`REG_SIZE] regs[NumRegs];

  // TODO: your code here
  assign regs[0] = 32'd0; // x0 is always zero
  // edited
  //assign rs1_data = (rs1 == 2)? 2: regs[rs1]; // 1st read port
  //assign rs2_data = (rs2 == 3)? 3: regs[rs2]; // 2nd read port

  assign rs1_data = regs[rs1]; // 1st read port
  assign rs2_data = regs[rs2]; // 2nd read port

  always_ff @(negedge clk) begin
    if (rst == 1'b1) begin
      for (i=0; i < NumRegs; i++) begin
        regs[i] <= 32'd0;
      end
    end else begin
      if ((we==1'b1) && (rd != 5'd0)) begin // if read and write happen at once
        regs[rd] <= rd_data;
      end
    end
  end

endmodule

/**
 * This enum is used to classify each cycle as it comes through the Writeback stage, identifying
 * if a valid insn is present or, if it is a stall cycle instead, the reason for the stall. The
 * enum values are mutually exclusive: only one should be set for any given cycle. These values
 * are compared against the trace-*.json files to ensure that the datapath is running with the
 * correct timing.
 *
 * You will need to set these values at various places within your pipeline, and propagate them
 * through the stages until they reach Writeback where they can be checked.
 */
typedef enum {
  /** invalid value, this should never appear after the initial reset sequence completes */
  CYCLE_INVALID = 0,
  /** a stall cycle that arose from the initial reset signal */
  CYCLE_RESET = 1,
  /** not a stall cycle, a valid insn is in Writeback */
  CYCLE_NO_STALL = 2,
  /** a stall cycle that arose from a taken branch/jump */
  CYCLE_TAKEN_BRANCH = 4,

  // the values below are only needed in HW5B

  /** a stall cycle that arose from a load-to-use stall */
  CYCLE_LOAD2USE = 8,
  /** a stall cycle that arose from a div/rem-to-use stall */
  CYCLE_DIV2USE = 16,
  /** a stall cycle that arose from a fence.i insn */
  CYCLE_FENCEI = 32
} cycle_status_e;

typedef struct packed {
  logic insn_lui;
  logic insn_auipc;
  logic insn_jal;
  logic insn_jalr;

  logic insn_beq;
  logic insn_bne;
  logic insn_blt;
  logic insn_bge;
  logic insn_bltu;
  logic insn_bgeu;

  logic insn_lb;
  logic insn_lh;
  logic insn_lw;
  logic insn_lbu;
  logic insn_lhu;

  logic insn_sb;
  logic insn_sh;
  logic insn_sw;

  logic insn_addi;
  logic insn_slti;
  logic insn_sltiu;
  logic insn_xori;
  logic insn_ori;
  logic insn_andi;

  logic insn_slli;
  logic insn_srli;
  logic insn_srai;

  logic insn_add;
  logic insn_sub ;
  logic insn_sll ;
  logic insn_slt;
  logic insn_sltu ;
  logic insn_xor ;
  logic insn_srl;
  logic insn_sra;
  logic insn_or;
  logic insn_and;

  logic insn_mul;
  logic insn_mulh;
  logic insn_mulhsu;
  logic insn_mulhu;
  logic insn_div;
  logic insn_divu;
  logic insn_rem;
  logic insn_remu;

  logic insn_ecall;
  logic insn_fence;
} exectue_ins;

/** state at the start of Decode stage */
typedef struct packed {
  logic [`REG_SIZE] pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e cycle_status;
  logic [4:0] rd_no;
  logic [4:0] rs1_no;
  logic [`REG_SIZE] rs1_data_temp;
  logic [4:0] rs2_no;
  logic [`REG_SIZE] rs2_data_temp;
  logic [6:0] insn_funct7;
  logic [2:0] insn_funct3;
  logic [`REG_SIZE] addr_to_dmem;
  logic [3:0] store_we_to_dmem;
  logic [`REG_SIZE] store_data_to_dmem;
  logic [`REG_SIZE] insn_imem;
  logic [`REG_SIZE] imm_i_sz_ext;
  logic [`OPCODE_SIZE] insn_opcode;
  exectue_ins exe_control;
} stage_decode_t;

typedef struct packed {
  logic [`REG_SIZE] pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e cycle_status;
  logic [4:0] rd_no;
  logic [`REG_SIZE] rd_val;
  logic [4:0] rs1_no;
  logic [`REG_SIZE] rs1_data_temp;
  logic [4:0] rs2_no;
  logic [`REG_SIZE] rs2_data_temp;
  logic [`REG_SIZE] addr_to_dmem;
  logic [3:0] store_we_to_dmem;
  logic [`REG_SIZE] store_data_to_dmem;
  logic [`REG_SIZE] insn_imem;
  logic [`REG_SIZE] imm_i_sz_ext;
  logic [`OPCODE_SIZE] insn_opcode;
  exectue_ins exe_control;
} stage_execute_t;

typedef struct packed {
  logic [`REG_SIZE] pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e cycle_status;
  logic [4:0] rd_no;
  logic [`REG_SIZE] rd_val;
  logic [4:0] rs1_no;
  logic [`REG_SIZE] rs1_data_temp;
  logic [4:0] rs2_no;
  logic [`REG_SIZE] rs2_data_temp;
  logic [`REG_SIZE] addr_to_dmem;
  logic [3:0] store_we_to_dmem;
  logic [`REG_SIZE] store_data_to_dmem;
  logic [`OPCODE_SIZE] insn_opcode;
  logic halt_sig;
  logic branch_taken;
  logic [`REG_SIZE] f_pc_next;
  //exectue_ins exe_control_m;
} stage_memory_t;

typedef struct packed {
  logic [`REG_SIZE] pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e cycle_status;
  logic [4:0] rd_no;
  logic [`REG_SIZE] rd_val;
  logic [4:0] rs1_no;
  logic [`REG_SIZE] rs1_data_temp;
  logic [4:0] rs2_no;
  logic [`REG_SIZE] rs2_data_temp;
  logic [`OPCODE_SIZE] insn_opcode;
  logic halt_sig;
} stage_writeback_t;

module DatapathPipelined (
    input wire clk,
    input wire rst,
    output logic [`REG_SIZE] pc_to_imem,
    input wire [`INSN_SIZE] insn_from_imem,
    // dmem is read/write
    output logic [`REG_SIZE] addr_to_dmem,
    input wire [`REG_SIZE] load_data_from_dmem,
    output logic [`REG_SIZE] store_data_to_dmem,
    output logic [3:0] store_we_to_dmem,

    output logic halt,

    // The PC of the insn currently in Writeback. 0 if not a valid insn.
    output logic [`REG_SIZE] trace_writeback_pc,
    // The bits of the insn currently in Writeback. 0 if not a valid insn.
    output logic [`INSN_SIZE] trace_writeback_insn,
    // The status of the insn (or stall) currently in Writeback. See cycle_status_e enum for valid values.
    output cycle_status_e trace_writeback_cycle_status
);

  // opcodes - see section 19 of RiscV spec
  localparam bit [`OPCODE_SIZE] OpcodeLoad = 7'b00_000_11;
  localparam bit [`OPCODE_SIZE] OpcodeStore = 7'b01_000_11;
  localparam bit [`OPCODE_SIZE] OpcodeBranch = 7'b11_000_11;
  localparam bit [`OPCODE_SIZE] OpcodeJalr = 7'b11_001_11;
  localparam bit [`OPCODE_SIZE] OpcodeMiscMem = 7'b00_011_11;
  localparam bit [`OPCODE_SIZE] OpcodeJal = 7'b11_011_11;

  localparam bit [`OPCODE_SIZE] OpcodeRegImm = 7'b00_100_11;
  localparam bit [`OPCODE_SIZE] OpcodeRegReg = 7'b01_100_11;
  localparam bit [`OPCODE_SIZE] OpcodeEnviron = 7'b11_100_11;

  localparam bit [`OPCODE_SIZE] OpcodeAuipc = 7'b00_101_11;
  localparam bit [`OPCODE_SIZE] OpcodeLui = 7'b01_101_11;

  // cycle counter, not really part of any stage but useful for orienting within GtkWave
  // do not rename this as the testbench uses this value
  logic [`REG_SIZE] cycles_current;
  always_ff @(posedge clk) begin
    if (rst) begin
      cycles_current <= 0;
    end else begin
      cycles_current <= cycles_current + 1;
    end
  end

  /***************/
  /* FETCH STAGE */
  /***************/
  logic [`REG_SIZE] f_pc_current;
  logic [`REG_SIZE] f_pc_next; //edited
  wire [`REG_SIZE] f_insn;
  cycle_status_e f_cycle_status;

  logic div_u_first;

  // program counter
  always_ff @(posedge clk) begin
    if (rst) begin
      f_pc_current <= 32'd0;
      // NB: use CYCLE_NO_STALL since this is the value that will persist after the last reset cycle
      f_cycle_status <= CYCLE_NO_STALL;
      //div_u_first <= 1'b0; 
    end else begin
      //if ((exe_control_temp.insn_div || exe_control_temp.insn_divu || exe_control_temp.insn_rem || exe_control_temp.insn_remu) && !div_u_first) begin
        //div_u_first <= 1'b1;
      //end else begin
        f_cycle_status <= CYCLE_NO_STALL;
        
        //edited
        if (branch_taken == 1'b1) begin
          f_pc_current <= f_pc_next;
        end else begin
          f_pc_current <= f_pc_current + 4;
        end
        //div_u_first <= 1'b0;
      //end
    end
  end
  // send PC to imem
  assign pc_to_imem = f_pc_current;
  assign f_insn = insn_from_imem;

  // Here's how to disassemble an insn into a string you can view in GtkWave.
  // Use PREFIX to provide a 1-character tag to identify which stage the insn comes from.
  wire [255:0] f_disasm;
  Disasm #(
      .PREFIX("F")
  ) disasm_0fetch (
      .insn  (f_insn),
      .disasm(f_disasm)
  );

   /* Edited: Instruction Decoding */
  // components of the instruction
  wire [6:0] insn_funct7;
  wire [4:0] insn_rs2;
  wire [4:0] insn_rs1;
  wire [2:0] insn_funct3;
  wire [4:0] insn_rd;
  wire [`OPCODE_SIZE] insn_opcode;

  // edited
  exectue_ins exe_control_temp;
  //logic [`REG_SIZE] rs1_data_temp;
  //logic [4:0] rs2;
  logic [`REG_SIZE] rs1_data_temp;
  logic [`REG_SIZE] rs2_data_temp;
  logic [4:0] rs2_val_or_not;
  //execute = rs1_data_temp;
  //alu_b = $signed(rs2_data_temp);

  // split R-type instruction - see section 2.2 of RiscV spec
  // edited: Need to decode it and then save it in the register. if I use the same decode
  // register, then values get delayed by one sample.
  assign {insn_funct7, insn_rs2, insn_rs1, insn_funct3, insn_rd, insn_opcode} = insn_from_imem;
    // B - conditionals
  wire [12:0] imm_b_temp;
  assign {imm_b_temp[12], imm_b_temp[10:5]} = insn_funct7, {imm_b_temp[4:1], imm_b_temp[11]} = insn_rd, imm_b_temp[0] = 1'b0;

  logic [`REG_SIZE] imm_b_sext_temp;
  assign imm_b_sext_temp = {{19{imm_b_temp[12]}}, imm_b_temp[12:0]};

  //assign rs2_val_or_not = insn_opcode != 
  /****************/
  /* DECODE STAGE */
  /****************/

  // this shows how to package up state in a `struct packed`, and how to pass it between stages
  stage_decode_t decode_state;
  always_ff @(posedge clk) begin
    if (rst) begin
      decode_state <= '{
        pc: 0,
        insn: 0,
        cycle_status: CYCLE_RESET,
        rd_no: 0,
        rs1_no: 0,
        rs1_data_temp: 0,
        rs2_no: 0,
        rs2_data_temp: 0,
        insn_funct7: 0,
        insn_funct3: 0,
        addr_to_dmem: 0,
        store_we_to_dmem: 0,
        store_data_to_dmem: 0,
        insn_imem: 0,
        imm_i_sz_ext: 0,
        insn_opcode: 0,
        exe_control: '{default:0}
      };
    end else begin
      begin
        if (branch_taken == 1'b1) begin
          decode_state <= 0;
        end else begin
          decode_state <= '{
          pc: f_pc_current,
          insn: f_insn,
          cycle_status: f_cycle_status,
          // Edited rd number not required for branching.
          rd_no: insn_opcode == 7'h63 ? 0 : insn_rd,// insn_rd, //insn_opcode == 7'h63 ? 0
          // Edited: don't want rs1 value for lui instruction
          rs1_no: insn_opcode == 7'h37 ? 0: insn_rs1,
          rs1_data_temp: rs1_data_temp,
          // edited: Important so that we don't propagate the rs2 signal
          // for instructions with immediate values
          rs2_no: ((insn_opcode == 7'h13) || (insn_opcode == 7'h37)) ? 0: insn_rs2,
          rs2_data_temp: rs2_data_temp,
          insn_funct7: insn_opcode == 7'h37 ? 0: insn_funct7,
          insn_funct3: insn_opcode == 7'h37 ? 0: insn_funct3,
          addr_to_dmem: 0,
          store_we_to_dmem: 0,
          store_data_to_dmem: 0,
          insn_imem: insn_from_imem,
          imm_i_sz_ext: 0,
          insn_opcode: insn_opcode,
          exe_control: '{default:0}
        };
      end
    end
  end


  // split R-type instruction - see section 2.2 of RiscV spec
  assign {insn_funct7, insn_rs2, insn_rs1, insn_funct3, insn_rd, insn_opcode} = decode_state.insn;

  // setup for I, S, B & J type instructions
  // I - short immediates and loads
  wire [11:0] imm_i;
  assign imm_i = decode_state.insn_imem[31:20];
  wire [4:0] imm_shamt = decode_state.insn_imem[24:20];

  // S - stores
  wire [11:0] imm_s;
  //assign imm_s[11:5] = insn_funct7, imm_s[4:0] = insn_rd;
  //assign imm_s[11:5] = decode_state.insn_funct7, imm_s[4:0] = decode_state.rd_no;
  assign imm_s[11:5] = decode_state.insn_funct7;
  assign imm_s[4:0] = decode_state.insn_imem[11:7];  //crutial edit

  // B - conditionals
  wire [12:0] imm_b;
  //assign {imm_b[12], imm_b[10:5]} = insn_funct7, {imm_b[4:1], imm_b[11]} = insn_rd, imm_b[0] = 1'b0;
  //assign {imm_b[12], imm_b[10:5]} = decode_state.insn_funct7, {imm_b[4:1], imm_b[11]} = decode_state.rd_no, imm_b[0] = 1'b0;
  assign {imm_b[12], imm_b[10:5]} = decode_state.insn_funct7, {imm_b[4:1], imm_b[11]} = decode_state.insn_imem[11:7], imm_b[0] = 1'b0;

  // J - unconditional jumps
  wire [20:0] imm_j;
  assign {imm_j[20], imm_j[10:1], imm_j[11], imm_j[19:12], imm_j[0]} = {decode_state.insn_imem[31:12], 1'b0};
  
  // U - Immidiates 
  wire [19:0] imm_u; 
  assign imm_u = decode_state.insn_imem[31:12];

  // edited: WD mux val
  logic [1:0] mux_val_wd;
  logic [`REG_SIZE] rs1_mux_data;
  logic [`REG_SIZE] rs2_mux_data;
  logic [4:0] wd_rd_no;
  assign wd_rd_no = wb_state.rd_no;

  // edited: Not sure why direct assignment doesn't work.
  // logic [`REG_SIZE] imm_i_sext = {{20{imm_i[11]}}, imm_i[11:0]};
  // logic [`REG_SIZE] imm_i_ext = {{20{1'b0}}, imm_i[11:0]};
  // logic [`REG_SIZE] imm_s_sext = {{20{imm_s[11]}}, imm_s[11:0]};
  // logic [`REG_SIZE] imm_b_sext = {{19{imm_b[12]}}, imm_b[12:0]};
  // logic [`REG_SIZE] imm_j_sext = {{11{imm_j[20]}}, imm_j[20:0]};
  // logic [`REG_SIZE] imm_u_ext = {{12{1'b0}},imm_u[19:0]};

  logic [`REG_SIZE] imm_i_sext;
  logic [`REG_SIZE] imm_i_ext;
  logic [`REG_SIZE] imm_s_sext;
  logic [`REG_SIZE] imm_b_sext;
  logic [`REG_SIZE] imm_j_sext;
  logic [`REG_SIZE] imm_u_ext;
  
  logic [`REG_SIZE] imm_i_sz_ext;

  // this works
  assign imm_i_sext = {{20{imm_i[11]}}, imm_i[11:0]};
  assign imm_i_ext = {{20{1'b0}}, imm_i[11:0]};
  assign imm_s_sext = {{20{imm_s[11]}}, imm_s[11:0]};
  assign imm_b_sext = {{19{imm_b[12]}}, imm_b[12:0]};
  assign imm_j_sext = {{11{imm_j[20]}}, imm_j[20:0]};
  assign imm_u_ext = {{12{1'b0}},imm_u[19:0]};

  // edited: user added
  // localparam bit [`OPCODE_SIZE] OpLui = 7'b01_101_11;
  // localparam bit [`OPCODE_SIZE] OpI = 7'b0010011;
  // localparam bit [`OPCODE_SIZE] OpR = 7'b0110011;
  // localparam bit [`OPCODE_SIZE] OpU = 7'b01_101_11;
  // localparam bit [`OPCODE_SIZE] Opecall = 7'b1110011;

  assign exe_control_temp.insn_lui = decode_state.insn_opcode == OpcodeLui;
  assign exe_control_temp.insn_auipc = decode_state.insn_opcode == OpcodeAuipc;
  assign exe_control_temp.insn_jal = decode_state.insn_opcode == OpcodeJal;
  assign exe_control_temp.insn_jalr = decode_state.insn_opcode == OpcodeJalr;

  assign exe_control_temp.insn_beq = decode_state.insn_opcode == OpcodeBranch && decode_state.insn_imem[14:12] == 3'b000;
  assign exe_control_temp.insn_bne = decode_state.insn_opcode == OpcodeBranch && decode_state.insn_imem[14:12] == 3'b001;
  assign exe_control_temp.insn_blt = decode_state.insn_opcode == OpcodeBranch && decode_state.insn_imem[14:12] == 3'b100;
  assign exe_control_temp.insn_bge = decode_state.insn_opcode == OpcodeBranch && decode_state.insn_imem[14:12] == 3'b101;
  assign exe_control_temp.insn_bltu = decode_state.insn_opcode == OpcodeBranch && decode_state.insn_imem[14:12] == 3'b110;
  assign exe_control_temp.insn_bgeu = decode_state.insn_opcode == OpcodeBranch && decode_state.insn_imem[14:12] == 3'b111;

  assign exe_control_temp.insn_lb = decode_state.insn_opcode == OpcodeLoad && decode_state.insn_imem[14:12] == 3'b000;
  assign exe_control_temp.insn_lh = decode_state.insn_opcode == OpcodeLoad && decode_state.insn_imem[14:12] == 3'b001;
  assign exe_control_temp.insn_lw = decode_state.insn_opcode == OpcodeLoad && decode_state.insn_imem[14:12] == 3'b010;
  assign exe_control_temp.insn_lbu = decode_state.insn_opcode == OpcodeLoad && decode_state.insn_imem[14:12] == 3'b100;
  assign exe_control_temp.insn_lhu = decode_state.insn_opcode == OpcodeLoad && decode_state.insn_imem[14:12] == 3'b101;

  assign exe_control_temp.insn_sb = decode_state.insn_opcode == OpcodeStore && decode_state.insn_imem[14:12] == 3'b000;
  assign exe_control_temp.insn_sh = decode_state.insn_opcode == OpcodeStore && decode_state.insn_imem[14:12] == 3'b001;
  assign exe_control_temp.insn_sw = decode_state.insn_opcode == OpcodeStore && decode_state.insn_imem[14:12] == 3'b010;

  assign exe_control_temp.insn_addi = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b000;
  assign exe_control_temp.insn_slti = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b010;
  assign exe_control_temp.insn_sltiu = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b011;
  assign exe_control_temp.insn_xori = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b100;
  assign exe_control_temp.insn_ori = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b110;
  assign exe_control_temp.insn_andi = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b111;

  assign exe_control_temp.insn_slli = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b001 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_srli = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b101 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_srai = decode_state.insn_opcode == OpcodeRegImm && decode_state.insn_imem[14:12] == 3'b101 && decode_state.insn_imem[31:25] == 7'b0100000;

  assign exe_control_temp.insn_add = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b000 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_sub  = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b000 && decode_state.insn_imem[31:25] == 7'b0100000;
  assign exe_control_temp.insn_sll = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b001 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_slt = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b010 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_sltu = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b011 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_xor = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b100 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_srl = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b101 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_sra  = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b101 && decode_state.insn_imem[31:25] == 7'b0100000;
  assign exe_control_temp.insn_or = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b110 && decode_state.insn_imem[31:25] == 7'd0;
  assign exe_control_temp.insn_and = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[14:12] == 3'b111 && decode_state.insn_imem[31:25] == 7'd0;

  assign exe_control_temp.insn_mul    = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b000;
  assign exe_control_temp.insn_mulh   = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b001;
  assign exe_control_temp.insn_mulhsu = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b010;
  assign exe_control_temp.insn_mulhu  = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b011;
  assign exe_control_temp.insn_div    = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b100;
  assign exe_control_temp.insn_divu   = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b101;
  assign exe_control_temp.insn_rem    = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b110;
  assign exe_control_temp.insn_remu   = decode_state.insn_opcode == OpcodeRegReg && decode_state.insn_imem[31:25] == 7'd1 && decode_state.insn_imem[14:12] == 3'b111;

  assign exe_control_temp.insn_ecall = decode_state.insn_opcode == OpcodeEnviron && decode_state.insn_imem[31:7] == 25'd0;
  assign exe_control_temp.insn_fence = decode_state.insn_opcode == OpcodeMiscMem;

  always_comb begin
    assign imm_i_sz_ext = 0;
    /* edited: Sending the immediate values that is only required */
    if (exe_control_temp.insn_jalr || exe_control_temp.insn_addi || exe_control_temp.insn_slti || exe_control_temp.insn_sltiu || exe_control_temp.insn_xori || exe_control_temp.insn_ori || exe_control_temp.insn_andi || (decode_state.insn_opcode == OpcodeLoad)) begin
      assign imm_i_sz_ext = imm_i_sext;
    end else if (exe_control_temp.insn_slli || exe_control_temp.insn_srli || exe_control_temp.insn_srai) begin
      assign imm_i_sz_ext = imm_i_ext;
    end else if (decode_state.insn_opcode == OpcodeStore) begin
      assign imm_i_sz_ext = imm_s_sext;
    end else if (decode_state.insn_opcode == OpcodeBranch) begin
      assign imm_i_sz_ext = imm_b_sext;
    end else if (decode_state.insn_opcode == OpcodeJal) begin
      assign imm_i_sz_ext = imm_j_sext;
    end else if ((decode_state.insn_opcode == OpcodeLui) || (decode_state.insn_opcode == OpcodeAuipc)) begin
      assign imm_i_sz_ext = imm_u_ext;
    end

    // edited: WD bypass implementation.
    rs1_mux_data = rs1_data_temp;
    rs2_mux_data = rs2_data_temp;

    mux_val_wd = 2'b0;

    if (wd_rd_no !=0) begin  
      if (wd_rd_no == decode_state.rs1_no) begin
        mux_val_wd = 2'b01;
        rs1_mux_data = wb_state.rd_val;
      end else if (wd_rd_no == decode_state.rs2_no) begin
        mux_val_wd = 2'b10;
        rs2_mux_data = wb_state.rd_val;
      end
    end

    execute_state_temp = '{
    pc: decode_state.pc,
    insn: decode_state.insn,
    cycle_status: decode_state.cycle_status,
    rd_no: decode_state.rd_no,
    rd_val: 0,
    rs1_no: decode_state.rs1_no,
    rs1_data_temp: rs1_mux_data, //rs1_data_temp,
    rs2_no: decode_state.rs2_no,
    rs2_data_temp: rs2_mux_data, //rs2_data_temp, 
    addr_to_dmem: decode_state.addr_to_dmem,
    store_we_to_dmem: decode_state.store_we_to_dmem,
    store_data_to_dmem: decode_state.store_data_to_dmem,
    insn_imem: decode_state.insn_imem,
    imm_i_sz_ext: imm_i_sz_ext,
    insn_opcode: decode_state.insn_opcode,
    exe_control: exe_control_temp //decode_state.exe_control
    };
    
  end

  /****************/
  /* EXECUTE STAGE */
  /****************/
  stage_execute_t execute_state;
  stage_execute_t execute_state_temp;

  always_ff @(posedge clk) begin
    if (rst) begin
      execute_state <= '{
        pc: 0,
        insn: 0,
        cycle_status: CYCLE_RESET,
        rd_no: 0,
        rd_val: 0,
        rs1_no: 0,
        rs1_data_temp: 0,
        rs2_no: 0,
        rs2_data_temp: 0,
        addr_to_dmem: 0,
        store_we_to_dmem: 0,
        store_data_to_dmem: 0,
        insn_imem: 0,
        imm_i_sz_ext: 0,
        insn_opcode: 0,
        exe_control: '{default:0}
      };
    end else begin
      begin
        // execute_state <= '{
        //   pc: decode_state.pc,
        //   insn: decode_state.insn,
        //   cycle_status: decode_state.cycle_status,
        //   rd_no: decode_state.rd_no,
        //   rd_val: 0,
        //   rs1_no: decode_state.rs1_no,
        //   rs1_data_temp: rs1_mux_data, //rs1_data_temp,
        //   rs2_no: decode_state.rs2_no,
        //   rs2_data_temp: rs2_mux_data, //rs2_data_temp, 
        //   addr_to_dmem: decode_state.addr_to_dmem,
        //   store_we_to_dmem: decode_state.store_we_to_dmem,
        //   store_data_to_dmem: decode_state.store_data_to_dmem,
        //   insn_imem: decode_state.insn_imem,
        //   imm_i_sz_ext: imm_i_sz_ext,
        //   insn_opcode: decode_state.insn_opcode,
        //   exe_control: exe_control_temp //decode_state.exe_control
        // };
        if (branch_taken == 1'b1) begin
            execute_state <= 0;
        end else begin
            execute_state <= execute_state_temp;
        end 
      end
    end
  end

  wire [255:0] e_disasm;
  Disasm #(
      .PREFIX("E")
  ) disasm_1execute (
      .insn  (execute_state.insn),
      .disasm(e_disasm)
  );

  logic illegal_insn;
  logic [4:0] rd; 
  logic [`REG_SIZE] rd_data;
  logic [4:0] rs1; 
  //logic [`REG_SIZE] rs1_data_temp;
  logic [4:0] rs2; 
  //logic [`REG_SIZE] rs2_data_temp;
  logic we_lui;
  
  logic alu_cin;
  logic [`REG_SIZE] alu_sum;
  logic [`REG_SIZE] alu_a, alu_b;
  
  logic halt_sig;
  logic halt_sig_temp;

  logic [31:0] address_bits;
  logic [`REG_SIZE] addr_to_dmem_temp;
  logic [`REG_SIZE] store_data_to_dmem_temp;
  logic [3:0] store_we_to_dmem_temp;
  logic [`REG_SIZE] pcCurrent_temp;

  logic [63:0] mult_res;
  logic [31:0] mult_res_signed;
  logic [63:0] mult_res_store;

  logic [31:0] i_dividend_temp;
  logic [31:0] i_divisor_temp;
  logic [31:0] o_remainder_temp;
  logic [31:0] o_quotient_temp;
  
  logic [`REG_SIZE] pc_inc;

  logic temp_rs1;
  logic temp_rs2;
  logic branch_taken;
  logic [`REG_SIZE] rd_temp;

  logic [`OPCODE_SIZE] insn_opcode_x;

  // edited: Mux values for mx and wx bypassing
  logic [4:0] m_rd_no;
  assign m_rd_no = memory_state.rd_no;
  
  logic [4:0] w_rd_no;
  assign w_rd_no = wb_state.rd_no;

  logic [4:0] x_rs1_no;
  assign x_rs1_no = execute_state.rs1_no;

  logic [4:0] x_rs2_no;
  assign x_rs2_no = execute_state.rs2_no;

  logic [`REG_SIZE] x_rs1_data;

  logic [`REG_SIZE] x_rs2_data;

  logic [3:0] mux_val_mx_wx;

  assign insn_opcode_x = execute_state.insn_opcode;

  always_comb begin
  //always @(posedge clk) begin
  // Using always ff doesn't work where there are subsequent 
  // instructions to be run.

  x_rs1_data = execute_state.rs1_data_temp;
  x_rs2_data = execute_state.rs2_data_temp;

  mux_val_mx_wx = 0;

  // This creates issue with wd bypass. need to fix this.
  // Edited: Important to specify m_rd_no !=0  && w_rd_no !=0 conditions.
  // or else randomly the mux values can change
  // Also don't set a value to be zero for a condition, 
  // by default mux_val_mx_wx might be set to zero as well.
  // if (m_rd_no !=0) begin  
  //   if (m_rd_no == x_rs1_no && m_rd_no != x_rs2_no) begin
  //     mux_val_mx_wx = 1;
  //     x_rs1_data = memory_state.rd_val;
  //   end if (m_rd_no == x_rs2_no && m_rd_no != x_rs1_no) begin
  //     mux_val_mx_wx = 2;
  //     x_rs2_data = memory_state.rd_val;
  //   end if (m_rd_no == x_rs1_no && m_rd_no == x_rs2_no) begin 
  //     x_rs2_data = memory_state.rd_val;
  //     x_rs1_data = memory_state.rd_val;
  //     // edited: case for handling double bypass
  //   end
  // end
  
  // if (w_rd_no !=0 && (m_rd_no != x_rs1_no || m_rd_no != x_rs2_no)) begin
  //   if (w_rd_no == x_rs1_no && w_rd_no != x_rs2_no) begin
  //     mux_val_mx_wx = 3;
  //     x_rs1_data = wb_state.rd_val;
  //   end if (w_rd_no == x_rs2_no && w_rd_no != x_rs1_no) begin
  //     mux_val_mx_wx = 4;
  //     x_rs2_data = wb_state.rd_val;
  //   end if (w_rd_no == x_rs1_no && w_rd_no == x_rs2_no) begin
  //     x_rs2_data = wb_state.rd_val;
  //     x_rs1_data = wb_state.rd_val;
  //     // edited: case for handling double bypass
  //   end 
  // end
  
  // // Edited: both wx and mx working at the same time.
  // if (m_rd_no !=0 && w_rd_no !=0) begin
  //   if (m_rd_no == x_rs1_no && w_rd_no == x_rs2_no) begin
  //     mux_val_mx_wx = 5;
  //     x_rs1_data = memory_state.rd_val;
  //     x_rs2_data = wb_state.rd_val;
  //   end if (m_rd_no == x_rs2_no && w_rd_no == x_rs1_no) begin
  //     mux_val_mx_wx = 6;
  //     x_rs2_data = memory_state.rd_val;
  //     x_rs1_data = wb_state.rd_val;
  //   end
    // end if (m_rd_no == x_rs1_no && w_rd_no == x_rs1_no) begin
    //   mux_val_mx_wx = 7;
    //   x_rs2_data = memory_state.rd_val;
    //   x_rs1_data = memory_state.rd_val;
    // end if (m_rd_no == x_rs2_no && w_rd_no == x_rs2_no) begin
    //   mux_val_mx_wx = 7;
    //   x_rs2_data = memory_state.rd_val;
    //   x_rs1_data = memory_state.rd_val;
    // end

    if (m_rd_no != 0 || w_rd_no != 0) begin
      if (m_rd_no == x_rs1_no && m_rd_no != x_rs2_no && m_rd_no != 0) begin
        mux_val_mx_wx = 1;
        x_rs1_data = memory_state.rd_val;
      end if (m_rd_no == x_rs2_no && m_rd_no != x_rs1_no  && m_rd_no != 0) begin
        mux_val_mx_wx = 2;
        x_rs2_data = memory_state.rd_val;
      end if (m_rd_no == x_rs1_no && m_rd_no == x_rs2_no && m_rd_no != 0) begin
        mux_val_mx_wx = 3;
        x_rs1_data = memory_state.rd_val;
        x_rs2_data = memory_state.rd_val;
      end if (w_rd_no == x_rs1_no && w_rd_no != x_rs2_no && w_rd_no != m_rd_no && w_rd_no != 0) begin
        mux_val_mx_wx = 4;
        x_rs1_data = wb_state.rd_val;
      end if (w_rd_no == x_rs2_no && w_rd_no != x_rs1_no && w_rd_no != m_rd_no && w_rd_no != 0) begin
        mux_val_mx_wx = 5;
        x_rs2_data = wb_state.rd_val;
      end if (w_rd_no == x_rs1_no && w_rd_no == x_rs2_no && w_rd_no != m_rd_no && w_rd_no != 0) begin
        mux_val_mx_wx = 6;
        x_rs2_data = wb_state.rd_val;
        x_rs1_data = wb_state.rd_val;
        // edited: case for handling double bypass
      end if (m_rd_no == x_rs1_no && w_rd_no == x_rs2_no && x_rs1_no != x_rs2_no && (w_rd_no != 0 && m_rd_no != 0)) begin
        mux_val_mx_wx = 7;
        x_rs1_data = memory_state.rd_val;
        x_rs2_data = wb_state.rd_val;
      end if (m_rd_no == x_rs2_no && w_rd_no == x_rs1_no && x_rs1_no != x_rs2_no && (w_rd_no != 0 && m_rd_no != 0)) begin
        mux_val_mx_wx = 8;
        x_rs2_data = memory_state.rd_val;
        x_rs1_data = wb_state.rd_val;
      end

    end

  //end

  // unique case (mux_val_mx_wx)
  //     3'b001: x_rs1_data = memory_state.rd_val;
  //     3'b010: x_rs2_data = memory_state.rd_val;
  //     3'b011: x_rs1_data = wb_state.rd_val;
  //     3'b100: x_rs2_data = wb_state.rd_val;
  //     default: ;
  // endcase

  alu_cin = 1'b0;

  // edited
  //f_pc_next = f_pc_current + 4;

  f_pc_next = 0;

  rd_temp = 32'd0;

  i_divisor_temp = 32'b0;
  i_dividend_temp = 32'b0;

  //store_we_to_dmem_temp = 4'b0;
  //store_data_to_dmem_temp = 32'b0;
  //halt_sig = 1'b0;
  halt_sig_temp = 1'b0;

  branch_taken = 1'b0;
  illegal_insn = 1'b0;
  mult_res = 64'b0;
  mult_res_signed = 32'b0;
  mult_res_store = 64'b0;
  alu_a = $signed(x_rs1_data);
  alu_b = $signed(x_rs2_data);
  //addr_to_dmem_temp = 32'b0; 
  //address_bits = 32'b0;
  //pc_inc = 32'd0;

  case (insn_opcode_x)
      OpcodeMiscMem: begin
          // treated as nop instruction 
          if(execute_state.exe_control.insn_fence) begin 
            //we_lui = 1'b0;
          end else begin
            illegal_insn = 1'b1;
          end 
    end
		
	  OpcodeEnviron: begin
          //we_lui = 1'b0;
          if(execute_state.exe_control.insn_ecall) begin
            //halt_sig = 1'b1;
            halt_sig_temp = 1'b1;
          end
       end

    OpcodeLui: begin
      if(execute_state.rd_no == 5'b0)
        rd_temp = 32'b0;
      else begin
        //rd_data = (imm_u_ext << 12);
        rd_temp = {execute_state.insn_imem[31:12], 12'd0};
      end
		end

    OpcodeJal: begin
      if (execute_state.exe_control.insn_jal) begin
        rd_temp = execute_state.pc + 32'd4;
        f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
        branch_taken = 1'b1;
      end 
      else begin 
        branch_taken = 1'b0;
      end
    end

    OpcodeJalr: begin
      if (execute_state.exe_control.insn_jalr) begin 
        rd_temp = execute_state.pc + 32'd4;
        f_pc_next = (($signed(x_rs1_data) + $signed(execute_state.imm_i_sz_ext)) & 32'hFFFFFFFE);
        //pcNext = pc_inc;
        branch_taken = 1'b1;
      end 
      else begin 
        branch_taken = 1'b0;
      end
    end 

    OpcodeBranch: begin
      //we_lui = 1'b0;
      if(execute_state.exe_control.insn_beq) begin 
        if(x_rs1_data == x_rs2_data) begin 
          f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
          branch_taken = 1'b1;
        end
        else begin 
          branch_taken = 1'b0;
        end 
      end else
      if(execute_state.exe_control.insn_bne)begin
        if (x_rs1_data != x_rs2_data) begin
          f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
          branch_taken = 1'b1;
          end
        else begin 
          branch_taken = 1'b0;
        end 
      end  
      else if(execute_state.exe_control.insn_blt)begin 
        if($signed(x_rs1_data) < $signed(x_rs2_data)) begin
          //pcNext = pcCurrent + imm_b_sext;
          f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
          branch_taken = 1'b1;
        end 
        else begin 
          branch_taken = 1'b0;
        end
      end
      else if(execute_state.exe_control.insn_bge)begin 
        if($signed(x_rs1_data) >= $signed(x_rs2_data)) begin
          //pcNext = pcCurrent + imm_b_sext;
          f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
          branch_taken = 1'b1;
        end
        else begin 
          branch_taken = 1'b0;
        end 
      end 
      else if(execute_state.exe_control.insn_bltu)begin 
        if($signed(x_rs1_data) < $unsigned(x_rs2_data)) begin
          //pcNext = pcCurrent + imm_b_sext;
          f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
          branch_taken = 1'b1;
        end
        else begin 
          branch_taken = 1'b0;
        end
      end
      else if(execute_state.exe_control.insn_bgeu)begin 
        if($signed(x_rs1_data) >= $unsigned(x_rs2_data)) begin
          //pcNext = pcCurrent + imm_b_sext;
          f_pc_next = execute_state.pc + execute_state.imm_i_sz_ext;
          branch_taken = 1'b1;
        end
        else begin 
          branch_taken = 1'b0;
        end
      end 
      else begin 
        //f_pc_next = f_pc_current + 32'd4;
      end       
    end 

    OpcodeRegImm: begin 
      if(execute_state.exe_control.insn_addi) begin 
          alu_a = x_rs1_data;
          //alu_b = imm_i_sext;
          alu_b = execute_state.imm_i_sz_ext;
          rd_temp = alu_sum;
      end
      else if (execute_state.exe_control.insn_slti) begin 
        if($signed(execute_state.imm_i_sz_ext) > $signed(x_rs1_data))
          rd_temp = 32'b1;
        else
          rd_temp = 32'b0;
      end
      else if(execute_state.exe_control.insn_sltiu) begin
        if($signed(x_rs1_data) < $unsigned(execute_state.imm_i_sz_ext))
          rd_temp = 32'b1;
        else
          rd_temp = 32'b0;
      end  
      else if(execute_state.exe_control.insn_xori) begin 
        rd_temp = $signed(x_rs1_data) ^ execute_state.imm_i_sz_ext;
      end 
      else if(execute_state.exe_control.insn_ori) begin
        rd_temp = $signed(x_rs1_data) | execute_state.imm_i_sz_ext;
      end
      else if(execute_state.exe_control.insn_andi) begin
        rd_temp = $signed(x_rs1_data) & execute_state.imm_i_sz_ext;
      end
      else if(execute_state.exe_control.insn_slli) begin
        rd_temp = (x_rs1_data << (execute_state.imm_i_sz_ext[4:0]));
      end
      else if(execute_state.exe_control.insn_srli) begin
        rd_temp = (x_rs1_data >> (execute_state.imm_i_sz_ext[4:0]));
      end
      else if(execute_state.exe_control.insn_srai) begin
        rd_temp = ($signed(x_rs1_data) >>> (execute_state.imm_i_sz_ext[4:0]));
      end
      else begin 
        illegal_insn = 1'b1;
      end 
    end

    OpcodeRegReg: begin
      if(execute_state.exe_control.insn_add) begin 
        alu_a = x_rs1_data;
        alu_b = x_rs2_data;
        rd_temp = alu_sum;
      end
      else if(execute_state.exe_control.insn_sub) begin 
        alu_a = x_rs1_data;
        alu_b = ~x_rs2_data;
        alu_cin = 1'b1;
        rd_temp = alu_sum;
      end
      else if(execute_state.exe_control.insn_sll) begin 
        rd_temp = x_rs1_data << x_rs2_data[4:0];
      end
      else if(execute_state.exe_control.insn_slt) begin  
        if($signed(x_rs1_data) < $signed(x_rs2_data)) 
          rd_temp = 32'b1;
        else 
          rd_temp = 32'b0;
      end
      else if(execute_state.exe_control.insn_sltu) begin 
        rd_temp = (x_rs1_data < $unsigned(x_rs2_data))? 32'b1:32'b0;
      end
      else if(execute_state.exe_control.insn_xor) begin 
        rd_temp = x_rs1_data ^ x_rs2_data;
      end
      else if(execute_state.exe_control.insn_srl) begin 
        rd_temp = x_rs1_data >> (x_rs2_data[4:0]);
      end
      else if(execute_state.exe_control.insn_sra) begin 
        rd_temp = $signed(x_rs1_data) >>> (x_rs2_data[4:0]);
      end
      else if(execute_state.exe_control.insn_or) begin 
        rd_temp = x_rs1_data | x_rs2_data;
      end
      else if(execute_state.exe_control.insn_and) begin 
        rd_temp = x_rs1_data & x_rs2_data;
      end
      else if(execute_state.exe_control.insn_mul)begin 
        mult_res = (x_rs1_data * x_rs2_data);
        rd_temp = mult_res[31:0];
      end 
      else if(execute_state.exe_control.insn_mulh)begin 
        mult_res = ($signed(x_rs1_data) * $signed(x_rs2_data));
        rd_temp = mult_res[63:32];
      end  
      else if(execute_state.exe_control.insn_mulhsu)begin //recheck
        mult_res_signed = (x_rs1_data[31]) ? (~x_rs1_data + 32'b1) : x_rs1_data;
        mult_res = (mult_res_signed * $unsigned(x_rs2_data));
        if(x_rs1_data[31]) begin
          mult_res_store = ~mult_res + 64'b1;
        end 
        else begin
          mult_res_store = mult_res;
        end 
        rd_temp = mult_res_store[63:32];                     
      end
      else if(execute_state.exe_control.insn_mulhu)begin 
        mult_res = ($unsigned(x_rs1_data) *  $unsigned(x_rs2_data));
        rd_temp = mult_res[63:32];
      end
      else if(execute_state.exe_control.insn_div)begin 
        i_dividend_temp = (x_rs1_data[31]) ? (~x_rs1_data + 32'b1) : x_rs1_data; 
        i_divisor_temp = (x_rs2_data[31]) ? (~x_rs2_data + 32'b1) : x_rs2_data;
        if(( x_rs1_data == 0 | x_rs2_data == 0)) begin  
            rd_temp = $signed(32'hFFFF_FFFF);             
        end 
        else if(x_rs1_data[31] != x_rs2_data[31]) begin
          rd_temp = (~o_quotient_temp + 32'b1);
        end 
        else begin 
          rd_temp = o_quotient_temp;
        end 
      end
      else if(execute_state.exe_control.insn_divu)begin 
        i_dividend_temp = $signed(x_rs1_data); 
        i_divisor_temp =  $unsigned(x_rs2_data);
        rd_temp = o_quotient_temp;
      end
      else if (execute_state.exe_control.insn_rem)begin 
        i_dividend_temp = (x_rs1_data[31]) ? (~x_rs1_data + 32'b1) : x_rs1_data; 
        i_divisor_temp = (x_rs2_data[31]) ? (~x_rs2_data + 32'b1) : x_rs2_data;
        if(x_rs1_data == 32'b0) begin  
            rd_temp = (x_rs2_data[31]) ? (~x_rs2_data + 32'b1) : x_rs2_data;             
        end 
        else if((x_rs1_data[31])) begin
          rd_temp = (~o_remainder_temp + 32'b1);
        end 
        else begin 
          rd_temp = o_remainder_temp;
        end
      end 
      else if(execute_state.exe_control.insn_remu)begin
        i_dividend_temp = $signed(x_rs1_data); 
        i_divisor_temp =  $unsigned(x_rs2_data);
        rd_temp = o_remainder_temp;
      end  
      else begin 
        illegal_insn = 1'b1;
      end                  
    end

    OpcodeStore: begin
    end

    OpcodeLoad: begin
    end

    default: begin
      illegal_insn = 1'b1;
    end 

    endcase

    // if(branch_taken == 1'b0) begin 
    //   f_pc_next = f_pc_current + 32'd4;
    // end

  end

  /****************/
  /* MEMORY STAGE */
  /****************/
  stage_memory_t memory_state;
  always_ff @(posedge clk) begin
    if (rst) begin
      memory_state <= '{
        pc: 0,
        insn: 0,
        cycle_status: CYCLE_RESET,
        rd_no: 0,
        rd_val: 0,
        rs1_no: 0,
        rs1_data_temp: 0,
        rs2_no: 0,
        rs2_data_temp: 0,
        addr_to_dmem: 0,
        store_we_to_dmem: 0,
        store_data_to_dmem: 0,
        insn_opcode: 0,
        halt_sig: 0,
        branch_taken: 0,
        f_pc_next: 0
      };
    end else begin
      begin
        memory_state <= '{
          pc: execute_state.pc,
          insn: execute_state.insn,
          cycle_status: execute_state.cycle_status,
          rd_no: execute_state.rd_no,
          rd_val: rd_temp,//execute_state.rd_val,
          rs1_no: execute_state.rs1_no,
          rs1_data_temp: x_rs1_data,
          rs2_no: execute_state.rs2_no,
          rs2_data_temp: x_rs2_data,
          addr_to_dmem: execute_state.addr_to_dmem,
          store_we_to_dmem: execute_state.store_we_to_dmem,
          store_data_to_dmem: execute_state.store_data_to_dmem,
          insn_opcode: execute_state.insn_opcode,
          halt_sig: halt_sig_temp,
          branch_taken: branch_taken,
          f_pc_next: f_pc_next
        };
      end
    end
  end
  wire [255:0] m_disasm;
  Disasm #(
      .PREFIX("M")
  ) disasm_1memory (
      .insn  (memory_state.insn),
      .disasm(m_disasm)
  );

  //assign addr_to_dmem = addr_to_dmem_temp;
  //assign store_we_to_dmem = store_we_to_dmem_temp;
  //assign store_data_to_dmem = store_data_to_dmem_temp;
  //assign halt = halt_sig;

  /****************/
  /* WRITEBACK STAGE */
  /****************/
  stage_writeback_t wb_state;
  always_ff @(posedge clk) begin
    if (rst) begin
      wb_state <= '{
        pc: 0,
        insn: 0,
        cycle_status: CYCLE_RESET,
        rd_no: 0,
        rd_val: 0,
        rs1_no: 0,
        rs1_data_temp: 0,
        rs2_no: 0,
        rs2_data_temp: 0,
        insn_opcode: 0,
        halt_sig: 0
      };

      ///f_cycle_status <= CYCLE_RESET;
    end else begin
      begin
        wb_state <= '{
          pc: memory_state.pc,
          insn: memory_state.insn,
          cycle_status: memory_state.cycle_status,
          rd_no: memory_state.rd_no,
          rd_val: memory_state.rd_val,
          rs1_no: memory_state.rs1_no,
          rs1_data_temp: memory_state.rs1_data_temp,
          rs2_no: memory_state.rs2_no,
          rs2_data_temp: memory_state.rs2_data_temp,
          insn_opcode: memory_state.insn_opcode,
          halt_sig: memory_state.halt_sig
        };
      end

      //f_cycle_status <= CYCLE_NO_STALL;
    end
  end


  wire [255:0] d_disasm;

  Disasm #(
      .PREFIX("D")
  ) disasm_1decode (
      .insn  (decode_state.insn),
      .disasm(d_disasm)
  );

  // TODO: your code here, though you will also need to modify some of the code above
  // TODO: the testbench requires that your register file instance is named `rf`
endmodule

module MemorySingleCycle #(
    parameter int NUM_WORDS = 512
) (
    // rst for both imem and dmem
    input wire rst,

    // clock for both imem and dmem. The memory reads/writes on @(negedge clk)
    input wire clk,

    // must always be aligned to a 4B boundary
    input wire [`REG_SIZE] pc_to_imem,

    // the value at memory location pc_to_imem
    output logic [`REG_SIZE] insn_from_imem,

    // must always be aligned to a 4B boundary
    input wire [`REG_SIZE] addr_to_dmem,

    // the value at memory location addr_to_dmem
    output logic [`REG_SIZE] load_data_from_dmem,

    // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
    input wire [`REG_SIZE] store_data_to_dmem,

    // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
    // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
    input wire [3:0] store_we_to_dmem
);

  // memory is arranged as an array of 4B words
  logic [`REG_SIZE] mem[NUM_WORDS];

  initial begin
    $readmemh("mem_initial_contents.hex", mem, 0);
  end

  always_comb begin
    // memory addresses should always be 4B-aligned
    assert (pc_to_imem[1:0] == 2'b00);
    assert (addr_to_dmem[1:0] == 2'b00);
  end

  localparam int AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam int AddrLsb = 2;

  always @(negedge clk) begin
    if (rst) begin
    end else begin
      insn_from_imem <= mem[{pc_to_imem[AddrMsb:AddrLsb]}];
    end
  end

  always @(negedge clk) begin
    if (rst) begin
    end else begin
      if (store_we_to_dmem[0]) begin
        mem[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
      end
      if (store_we_to_dmem[1]) begin
        mem[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
      end
      if (store_we_to_dmem[2]) begin
        mem[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
      end
      if (store_we_to_dmem[3]) begin
        mem[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
      end
      // dmem is "read-first": read returns value before the write
      load_data_from_dmem <= mem[{addr_to_dmem[AddrMsb:AddrLsb]}];
    end
  end
endmodule

/* This design has just one clock for both processor and memory. */
module RiscvProcessor (
    input  wire  clk,
    input  wire  rst,
    output logic halt,
    output wire [`REG_SIZE] trace_writeback_pc,
    output wire [`INSN_SIZE] trace_writeback_insn,
    output cycle_status_e trace_writeback_cycle_status
);

  wire [`INSN_SIZE] insn_from_imem;
  wire [`REG_SIZE] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [3:0] mem_data_we;

  MemorySingleCycle #(
      .NUM_WORDS(8192)
  ) the_mem (
      .rst                (rst),
      .clk                (clk),
      // imem is read-only
      .pc_to_imem         (pc_to_imem),
      .insn_from_imem     (insn_from_imem),
      // dmem is read-write
      .addr_to_dmem       (mem_data_addr),
      .load_data_from_dmem(mem_data_loaded_value),
      .store_data_to_dmem (mem_data_to_write),
      .store_we_to_dmem   (mem_data_we)
  );

  DatapathPipelined datapath (
      .clk(clk),
      .rst(rst),
      .pc_to_imem(pc_to_imem),
      .insn_from_imem(insn_from_imem),
      .addr_to_dmem(mem_data_addr),
      .store_data_to_dmem(mem_data_to_write),
      .store_we_to_dmem(mem_data_we),
      .load_data_from_dmem(mem_data_loaded_value),
      .halt(halt),
      .trace_writeback_pc(trace_writeback_pc),
      .trace_writeback_insn(trace_writeback_insn),
      .trace_writeback_cycle_status(trace_writeback_cycle_status)
  );

endmodule
