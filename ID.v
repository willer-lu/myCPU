`include "lib/defines.vh"
module ID(
    input wire clk,  // 时钟信号,
    input wire rst,  // 复位信号
    // input wire flush,
    input wire [`StallBus-1:0] stall,
    //stallBus = 6
    output wire stallreq,  //暂停请求

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus, //使能信号与指令地址
    // `define IF_TO_ID_WD 33
    // `define ID_TO_EX_WD 159
    // `define EX_TO_MEM_WD 76
    // `define MEM_TO_WB_WD 271
    // `define BR_WD 33
    // `define DATA_SRAM_WD 69
    // `define WB_TO_RF_WD 38
    // `define StallBus 6
    // `define NoStop 1'b0
    // `define Stop 1'b1
    input wire [31:0] inst_sram_rdata, //指令内容

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus, //WB段输入的内容
    
    //处于执行阶段指令要写入的寄存器信息
    input wire ex_rf_we, 
    input wire [4:0] ex_rf_waddr,
    input wire [31:0] ex_ex_result,
    
    //处于访存阶段指令要写入的寄存器信息
    input wire mem_rf_we, 
    input wire [4:0] mem_rf_waddr,
    input wire [31:0] mem_rf_wdata,
    
    
    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,//即ID到EX段的内容

    output wire [`BR_WD-1:0] br_bus    
    
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;
    wire [31:0] inst;  //译码阶段的指令
    wire [31:0] id_pc;   //译码阶段的地址
    wire ce;  //使能线
 
    
  
  //WB段输入的相关内容
    wire wb_rf_we;
    wire [4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    //
    ////          regfile
    ////    	.clk    (clk    ),
    ////    .raddr1 (rs ),
    ////    .rdata1 (rdata1 ),
    ////    .raddr2 (rt ),
    ////    .rdata2 (rdata2 ),
    ////    .we     (wb_rf_we     ),
    ////    .waddr  (wb_rf_waddr  ),
    ////    .wdata  (wb_rf_wdata  )
    ////
    //对指令进行译码操作
    always @ (posedge clk) begin
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        // else if (flush) begin
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        else if (stall[1]==`NoStop) begin
            if_to_id_bus_r <= if_to_id_bus;
        end
    end
    //输入指令
    assign inst = inst_sram_rdata;
    assign {   //使能信号 指令地址
        ce,
        id_pc
    } = if_to_id_bus_r;
    assign {   //WB段输入的内容
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    wire [5:0] opcode;  //操作码
    wire [4:0] rs,rt,rd,sa; //源寄存器与目的寄存器(R-R)，移位量
    wire [5:0] func;    //具体的运算操作编码
    wire [15:0] imm;    //立即数(I类指令)
    wire [25:0] instr_index; //与PC相加的偏移量(J类指令)
    wire [19:0] code;  //异常处理指令中的code段  系统调用指令syscall
    wire [4:0] base;   //基址(寄存器储存的地址)
    wire [15:0] offset;  //偏移量
    wire [2:0] sel;    

    wire [63:0] op_d, func_d;  //操作的具体内容
    wire [31:0] rs_d, rt_d, rd_d, sa_d; //寄存器或移位量具体值

    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2; //控制reg1 reg2内容
    wire [11:0] alu_op;  //不同子类型操作

    wire data_ram_en;
    wire [3:0] data_ram_wen;
    
    wire rf_we;  //判断指令是否有要写入的目的寄存器
    wire [4:0] rf_waddr;  //指令要写入的目的寄存器的地址
    wire sel_rf_res;
    wire [2:0] sel_rf_dst;

    wire [31:0] rdata1, rdata2, uprdata1, uprdata2; //从regfile输入的数据 与更新后的值

    ///如何例化regfile
    regfile u_regfile(
    	.clk    (clk    ),
        .raddr1 (rs ),
        .rdata1 (rdata1 ),
        ///regfile output
        .raddr2 (rt ),
        .rdata2 (rdata2 ),
        ///regfile output
        .we     (wb_rf_we     ),
        .waddr  (wb_rf_waddr  ),
        .wdata  (wb_rf_wdata  )
    );

    assign opcode = inst[31:26];   //根据不同的指令进行切片
    assign rs = inst[25:21];
    assign rt = inst[20:16];
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];
    assign sel = inst[2:0];

    wire inst_ori, inst_lui, inst_addiu, inst_beq, inst_subu;//已有的指令类型
    wire inst_jal, inst_jr, inst_addu, inst_bne, inst_or ;
    wire inst_sll;
    wire inst_lw;
    //ori立即数位或 ori rt rs im
    //lui寄存器高半部分置立即数  lui rt im
    //addiu加立即数 addiu rt rs im
    //beq相等转移 beq rs rt offset
    //subu 将 rs与 rt相减，结果写入 rd  subu rs rt rd sham func
    //jal 无条件跳转 jal index
    //jr 无条件跳转。跳转目标为寄存器 rs 中的值 jr rs 10 5 func
    //addu 将 rs 与 rt 相加，结果写入 rd  addu rs rt rd sham func
    // rs 不等于 rt 则转移 bne rs rt offset
    //由立即数 sa 指定移位量，对rt的值进行左移  写入rd中  SLL rd, rt, sa
    //rs中的值与rt中的值按位逻辑或，结果写入rd中     OR rd, rs, rt
    wire op_add, op_sub, op_slt, op_sltu; //加、减、有符号小于置1、无符号小于设置1
    wire op_and, op_nor, op_or, op_xor;//位与、位或非、位或、位异或
    wire op_sll, op_srl, op_sra, op_lui;//立即数逻辑左移、立即数逻辑右移、立即数算术右移、寄存器高半部分置立即数

//6位译码器与5位译码器  分别用来确定操作码和寄存器
    decoder_6_64 u0_decoder_6_64(
    	.in  (opcode  ),
        .out (op_d )
    );
    //独热码变一进制
    decoder_6_64 u1_decoder_6_64(
    	.in  (func  ),
        .out (func_d )
    );
    
    decoder_5_32 u0_decoder_5_32(
    	.in  (rs  ),
        .out (rs_d )
    );

    decoder_5_32 u1_decoder_5_32(
    	.in  (rt  ),
        .out (rt_d )
    );

    
    assign inst_ori     = op_d[6'b00_1101];
    assign inst_lui     = op_d[6'b00_1111];
    assign inst_addiu   = op_d[6'b00_1001];
    assign inst_beq     = op_d[6'b00_0100];
    assign inst_subu    = op_d[6'b00_0000]&func_d[6'b10_0011];
    assign inst_jal     = op_d[6'b00_0011];
    assign inst_jr      = op_d[6'b00_0000]&func_d[6'b00_1000];
    assign inst_addu    = op_d[6'b00_0000]&func_d[6'b10_0001];
    assign inst_bne     = op_d[6'b00_0101];
    assign inst_sll     = op_d[6'b00_0000]&func_d[6'b00_0000];
    assign inst_or      = op_d[6'b00_0000]&func_d[6'b10_0101];
    assign inst_lw      = op_d[6'b10_0011];
    //  激活信号


    // rs to reg1
    assign sel_alu_src1[0] = inst_ori | inst_addiu |inst_subu |inst_addu|inst_or|inst_lw;
    // pc to reg1
    assign sel_alu_src1[1] = inst_jal ;
    // sa_zero_extend to reg1 偏移量
    assign sel_alu_src1[2] = inst_sll;
    
    // rt to reg2
    assign sel_alu_src2[0] = inst_subu |inst_addu|inst_sll|inst_or;
    // imm_sign_extend to reg2
    assign sel_alu_src2[1] = inst_lui | inst_addiu|inst_lw;
    // 32'b8 to reg2
    assign sel_alu_src2[2] = inst_jal;
    // imm_zero_extend to reg2
    assign sel_alu_src2[3] = inst_ori;
    //替代rt

    assign op_add = inst_addiu |inst_jal|inst_addu|inst_lw;
    assign op_sub = inst_subu;
    assign op_slt = 1'b0;
    assign op_sltu = 1'b0;
    assign op_and = 1'b0;
    assign op_nor = 1'b0;
    assign op_or = inst_ori|inst_or;
    assign op_xor = 1'b0;
    assign op_sll = inst_sll;
    assign op_srl = 1'b0;
    assign op_sra = 1'b0;
    assign op_lui = inst_lui;

    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};



    // load and store enable
    assign data_ram_en = inst_lw;

    // write enable
    assign data_ram_wen = 1'b0;



    // regfile store enable
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu |inst_jal|inst_addu|inst_sll|inst_or|inst_lw;
    //链接和跳转


    // store in [rd]
    assign sel_rf_dst[0] = inst_subu|inst_addu|inst_sll|inst_or;
    // store in [rt] 
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu|inst_lw;
    // store in [31]
    assign sel_rf_dst[2] = inst_jal;

    // sel for regfile address
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    // 0 from alu_res ; 1 from ld_res
    assign sel_rf_res = 1'b0; //result  mem阶段使用
       
    assign uprdata1 = ((ex_rf_we == 1'b1) && (ex_rf_waddr == rs))  ?  ex_ex_result :(((mem_rf_we == 1'b1) && (mem_rf_waddr == rs))  ?  mem_rf_wdata : (((wb_rf_we == 1'b1) && (wb_rf_waddr == rs))? wb_rf_wdata: rdata1)   );
	assign uprdata2 = ((ex_rf_we == 1'b1) && (ex_rf_waddr == rt))  ?  ex_ex_result :(((mem_rf_we == 1'b1) && (mem_rf_waddr == rt))  ?  mem_rf_wdata : (((wb_rf_we == 1'b1) && (wb_rf_waddr == rt))? wb_rf_wdata: rdata2)   );


    //////////////////////////////////////////////////////////////在这一步之前改变rdata
    assign id_to_ex_bus = {
        id_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        uprdata1,         // 63:32
        uprdata2          // 31:0
    };
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    wire br_e;
    wire [31:0] br_addr;
    wire rs_eq_rt;
    wire rs_ge_z;
    wire rs_gt_z;
    wire rs_le_z;
    wire rs_lt_z;
    wire [31:0] pc_plus_4;
    assign pc_plus_4 = id_pc + 32'h4;

    assign rs_eq_rt = (uprdata1 == uprdata2);

    assign br_e =  inst_jal |inst_jr |(inst_beq & rs_eq_rt)|(inst_bne & (!rs_eq_rt)) ;
    assign br_addr =  inst_jal  ?  {pc_plus_4 [31:28],inst[25:0],2'b0}:
                      inst_jr ? uprdata1 :
                      (inst_beq|inst_bne) ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :
                      32'b0;

    assign br_bus = {
        br_e,
        br_addr
    };
    


endmodule
