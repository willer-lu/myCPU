`include "lib/defines.vh"
module ID(
    input wire clk,  // 时钟信号,
    input wire rst,  // 复位信号

    input wire [`StallBus-1:0] stall,
    //stallBus = 6
    output wire stallreq,  //暂停请求

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus, //使能信号与指令地址
 
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

    output wire [`BR_WD-1:0] br_bus,
    input wire is_lw,
    input wire [65:0] ex_hilo
);
    
    
    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;
    //reg [`IC_TO_ID_WD-1:0] ic_to_id_bus;
    wire [31:0] inst;  //译码阶段的指令
    wire [31:0] id_pc;   //译码阶段的地址
    wire ce;  //使能线

  
  //WB段输入的相关内容
    wire wb_rf_we;
    wire [4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;

    always @ (posedge clk) begin
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
//       else if (flush) begin
//            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
//        end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        else if (stall[1]==`NoStop) begin
            if_to_id_bus_r <= if_to_id_bus;
        end
    end
    //输入指令
//    reg[31:0] instreg;
//    reg flag;
//        always @ (posedge clk) begin
//        if (stall[2]==`Stop && stall[3]==`NoStop) begin
//            flag <= 1'b1;
//            instreg <=inst_sram_rdata;
//        end
//        else begin
//            flag <= 1'b0;
//            instreg <=32'b0;
//        end
//    end
//    assign inst = flag?instreg:inst_sram_rdata;
    reg flag;
        always @ (posedge clk) begin
        if (stall[1]==`Stop) begin
            flag <= 1'b1;
        end
        else begin
            flag <= 1'b0;
        end
    end
    assign inst = flag?inst:inst_sram_rdata;    

    
    
    
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
    wire data_ram_wen;
    wire [3:0] sl;//区分不同 的l s指令
    
    wire rf_we;  //判断指令是否有要写入的目的寄存器
    wire [4:0] rf_waddr;  //指令要写入的目的寄存器的地址
    wire sel_rf_res;
    wire [2:0] sel_rf_dst;

    wire [31:0] rdata1, rdata2, uprdata1, uprdata2; //从regfile输入的数据 与更新后的值
    wire hir,lor,hiwen,lowen;
    wire [31:0] hilodata,hidata,lodata;
   
    assign {
        hiwen,
        lowen,
        hidata,
        lodata
       } = ex_hilo;
    ///如何例化regfile
    regfile u_regfile(
    	.clk    (clk    ),
    	.rst    (rst),
        .raddr1 (rs ),
        .rdata1 (rdata1 ),
        ///regfile output
        .raddr2 (rt ),
        .rdata2 (rdata2 ),
        ///regfile output
        .we     (wb_rf_we     ),
        .waddr  (wb_rf_waddr  ),
        .wdata  (wb_rf_wdata  ),
        .hiwe   (hiwen),
        .lowe   (lowen),
        .hir    (hir),
        .lor    (lor),
        .hi_i   (hidata),
        .lo_i   (lodata),
        .hilodata(hilodata)
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
    assign sel = inst[2:0];  //特权指令

    wire inst_ori, inst_lui, inst_addiu, inst_beq, inst_subu;//已有的指令类型
    wire inst_jal, inst_jr, inst_addu, inst_bne, inst_or ;
    wire inst_sll, inst_lw, inst_xor, inst_sw, inst_sltu;
    wire inst_slt, inst_and, inst_nor,inst_srl,inst_sra;
    wire inst_andi,inst_add,inst_addi,inst_sub,inst_slti;
    wire inst_sltiu,inst_xori,inst_j,inst_sllv,inst_srav;
    wire inst_srlv,inst_bgez,inst_bgtz,inst_blez,inst_bltz;
    wire inst_bgezal,inst_bltzal,inst_jalr,inst_div,inst_mult;
    wire inst_multu,inst_divu,inst_mfhi,inst_mthi,inst_mflo;
    wire inst_mtlo,inst_lb,inst_lbu,inst_lh,inst_lhu;
    wire inst_sb,inst_sh,inst_syscall,inst_break,inst_eret;

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
    assign inst_xor     = op_d[6'b00_0000]&func_d[6'b10_0110];
    assign inst_sw      = op_d[6'b10_1011];
    assign inst_sltu    = op_d[6'b00_0000]&func_d[6'b10_1011];
    assign inst_slt     = op_d[6'b00_0000]&func_d[6'b10_1010];
    assign inst_and     = op_d[6'b00_0000]&func_d[6'b10_0100];
    assign inst_nor     = op_d[6'b00_0000]&func_d[6'b10_0111];
    assign inst_srl     = op_d[6'b00_0000]&func_d[6'b00_0010];
    assign inst_sra     = op_d[6'b00_0000]&func_d[6'b00_0011];
    assign inst_andi    = op_d[6'b00_1100];
    assign inst_add     = op_d[6'b00_0000]&func_d[6'b10_0000];
    assign inst_addi    = op_d[6'b00_1000];
    assign inst_sub     = op_d[6'b00_0000]&func_d[6'b10_0010];
    assign inst_slti    = op_d[6'b00_1010];
    assign inst_sltiu   = op_d[6'b00_1011];
    assign inst_xori    = op_d[6'b00_1110];
    assign inst_j       = op_d[6'b00_0010];
    assign inst_sllv    = op_d[6'b00_0000]&func_d[6'b00_0100];
    assign inst_srav    = op_d[6'b00_0000]&func_d[6'b00_0111];
    assign inst_srlv    = op_d[6'b00_0000]&func_d[6'b00_0110];
    assign inst_bgez    = op_d[6'b00_0001]&rt_d[5'b00001];
    assign inst_bgtz    = op_d[6'b00_0111];
    assign inst_blez    = op_d[6'b00_0110];
    assign inst_bltz    = op_d[6'b00_0001]&rt_d[5'b00000];
    assign inst_bgezal  = op_d[6'b00_0001]&rt_d[5'b10001];
    assign inst_bltzal  = op_d[6'b00_0001]&rt_d[5'b10000];
    assign inst_jalr    = op_d[6'b00_0000]&func_d[6'b00_1001];
    assign inst_div     = op_d[6'b00_0000]&func_d[6'b01_1010];
    assign inst_divu    = op_d[6'b00_0000]&func_d[6'b01_1011];
    assign inst_mult    = op_d[6'b00_0000]&func_d[6'b01_1000];
    assign inst_multu   = op_d[6'b00_0000]&func_d[6'b01_1001]; 
    assign inst_mfhi    = op_d[6'b00_0000]&func_d[6'b01_0000]; 
    assign inst_mthi    = op_d[6'b00_0000]&func_d[6'b01_0001];
    assign inst_mflo    = op_d[6'b00_0000]&func_d[6'b01_0010];
    assign inst_mtlo    = op_d[6'b00_0000]&func_d[6'b01_0011];
    assign inst_lb      = op_d[6'b10_0000];
    assign inst_lbu     = op_d[6'b10_0100];
    assign inst_lh      = op_d[6'b10_0001];
    assign inst_lhu     = op_d[6'b10_0101];
    assign inst_sb      = op_d[6'b10_1000];
    assign inst_sh      = op_d[6'b10_1001];
    assign inst_syscall = op_d[6'b00_0000]&func_d[6'b001_100];
    assign inst_break   = op_d[6'b00_0000]&func_d[6'b001_101];
    assign inst_eret    = op_d[6'b01_0000]&func_d[6'b01_1000];
    //  激活信号
    

    // rs to reg1
    assign sel_alu_src1[0] = inst_ori | inst_addiu |inst_subu |inst_addu|inst_or|inst_lw
                             |inst_xor|inst_sw |inst_sltu|inst_slt|inst_and|inst_nor
                             |inst_andi|inst_add|inst_addi|inst_sub|inst_slti|inst_sltiu
                             |inst_xori|inst_sllv|inst_srav|inst_srlv|inst_div
                             |inst_divu|inst_mult|inst_multu|inst_mflo|inst_mfhi
                             |inst_lb|inst_lbu|inst_lh|inst_lhu|inst_sb|inst_sh;
    // pc to reg1
    assign sel_alu_src1[1] = inst_jal|inst_bgezal|inst_bltzal|inst_jalr;
    // sa_zero_extend to reg1 偏移量
    assign sel_alu_src1[2] = inst_sll|inst_srl|inst_sra;
    
    // rt to reg2
    assign sel_alu_src2[0] = inst_subu |inst_addu|inst_sll|inst_or|inst_xor|inst_sltu|inst_slt|
                             inst_and|inst_nor|inst_srl|inst_sra|inst_add|inst_sub|inst_sllv|
                             inst_srav|inst_srlv|inst_div|inst_mfhi|inst_mflo
                             |inst_divu|inst_mult|inst_multu;
    // imm_sign_extend to reg2
    assign sel_alu_src2[1] = inst_lui | inst_addiu|inst_lw|inst_sw|inst_addi|inst_slti
                            |inst_sltiu|inst_lb|inst_lbu|inst_lh|inst_lhu|inst_sb|inst_sh;
    // 32'b8 to reg2
    assign sel_alu_src2[2] = inst_jal|inst_bgezal|inst_bltzal|inst_jalr;
    // imm_zero_extend to reg2
    assign sel_alu_src2[3] = inst_ori|inst_andi|inst_xori;
    //替代rt

    assign op_add = inst_addiu |inst_jal|inst_addu|inst_lw|inst_sw|inst_add|inst_addi
                    |inst_bgezal|inst_bltzal|inst_jalr|inst_lb|inst_lbu|inst_lh|inst_lhu|inst_sb|inst_sh;
    assign op_sub = inst_subu|inst_sub;
    assign op_slt = inst_slt|inst_slti;
    assign op_sltu = inst_sltu|inst_sltiu;
    assign op_and = inst_and|inst_andi|inst_mflo|inst_mfhi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori|inst_or;
    assign op_xor = inst_xor|inst_xori;
    assign op_sll = inst_sll|inst_sllv;
    assign op_srl = inst_srl|inst_srlv;
    assign op_sra = inst_sra|inst_srav;
    assign op_lui = inst_lui;
    
    

    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};



    // load and store enable
    assign data_ram_en = inst_lw|inst_sw|inst_lb|inst_lbu|inst_lh
                         |inst_lhu| inst_sb |inst_sh;

    // write enable
    assign data_ram_wen = inst_sw| inst_sb |inst_sh;
    
    assign sl = inst_lw  ? 4'b0001 
               :inst_sw  ? 4'b0010 
               :inst_lb  ? 4'b0011
               :inst_lbu ? 4'b0100
               :inst_lh  ? 4'b0101
               :inst_lhu ? 4'b0110
               :inst_sb  ? 4'b0111
               :inst_sh  ? 4'b1000
                :4'b0000;

    assign excepttype_is_syscall = inst_syscall;
    assign excepttype_is_eret =inst_eret;

    // regfile store enable
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu |inst_jal|inst_addu
                   |inst_sll|inst_or|inst_lw||inst_xor|inst_sltu|inst_slt|inst_and
                   |inst_nor|inst_srl|inst_sra|inst_andi|inst_add|inst_addi|inst_sub
                   |inst_slti|inst_sltiu|inst_xori|inst_sllv|inst_srav|inst_srlv|
                   inst_bgezal|inst_bltzal|inst_jalr|inst_mfhi|inst_mflo|inst_lb
                   |inst_lbu|inst_lh|inst_lhu;
    //链接和跳转


    // store in [rd]
    assign sel_rf_dst[0] = inst_subu|inst_addu|inst_sll|inst_or||inst_xor|inst_sltu|inst_slt|
                           inst_and|inst_nor|inst_srl|inst_sra|inst_add|inst_sub|inst_sllv|
                           inst_srav|inst_srlv|inst_jalr|inst_mfhi|inst_mflo;
    // store in [rt] 
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu|inst_lw|inst_sw|inst_andi
                            |inst_addi|inst_slti|inst_sltiu|inst_xori|inst_lb|inst_lbu
                            |inst_lh|inst_lhu;
    // store in [31]
    assign sel_rf_dst[2] = inst_jal|inst_bgezal|inst_bltzal;

    // sel for regfile address
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    // 0 from alu_res ; 1 from ld_res
    assign sel_rf_res = inst_lw|inst_lb|inst_lbu|inst_lh|inst_lhu; //result  mem阶段使用
    assign stallreq = (is_lw &&((rs == ex_rf_waddr)||(rt == ex_rf_waddr)));

    assign hir = inst_mfhi;
    assign lor = inst_mflo;
    wire [31:0] mfdata;
    assign mfdata = (inst_mfhi & hiwen)? hidata:
                   inst_mfhi? hilodata:
                    (inst_mflo & lowen)? lodata:
                    inst_mflo ? hilodata:
                    32'b0;      
    assign uprdata1 = (inst_mfhi|inst_mflo)?mfdata:
                        ((ex_rf_we == 1'b1) && (ex_rf_waddr == rs))  ?  ex_ex_result :
                      ((mem_rf_we == 1'b1) && (mem_rf_waddr == rs))  ?  mem_rf_wdata :
                       ((wb_rf_we == 1'b1) && (wb_rf_waddr == rs))? wb_rf_wdata: 
                       rdata1;
	assign uprdata2 = (inst_mfhi|inst_mflo)?mfdata:    
	                   ((ex_rf_we == 1'b1) && (ex_rf_waddr == rt))  ?  ex_ex_result :
	                  ((mem_rf_we == 1'b1) && (mem_rf_waddr == rt))  ?  mem_rf_wdata : 
	                   ((wb_rf_we == 1'b1) && (wb_rf_waddr == rt))? wb_rf_wdata: 
	                   rdata2   ;


    //////////////////////////////////////////////////////////////在这一步之前改变rdata
    assign id_to_ex_bus = {
        inst_div,
        inst_divu,
        inst_mult,
        inst_multu,
        inst_mthi,
        inst_mtlo,
        id_pc,          // 155:124
        inst,           // 123:92
        alu_op,         // 91:80
        sel_alu_src1,   // 79:77
        sel_alu_src2,   // 76:73
        sl,
        data_ram_en,    // 72
        data_ram_wen,   // 71
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
    assign rs_ge_z  = (uprdata1[31] == 1'b0);
    assign rs_gt_z  = (uprdata1[31] == 1'b0 &&uprdata1!= 32'h00000000);
    assign rs_le_z  = (uprdata1[31] == 1'b1 ||uprdata1== 32'h00000000);
    assign rs_lt_z  = (uprdata1[31] == 1'b1);

    assign br_e =  inst_j|inst_jal |inst_jr |(inst_beq & rs_eq_rt)|(inst_bne & (!rs_eq_rt))|
                   (inst_bgez&rs_ge_z)|(inst_bgtz&rs_gt_z)|(inst_blez&rs_le_z)|(inst_bltz&rs_lt_z)|
                   (inst_bgezal&rs_ge_z)|(inst_bltzal&rs_lt_z)|inst_jalr;
    assign br_addr =  (inst_jal|inst_j)  ?  {pc_plus_4 [31:28],inst[25:0],2'b0}:
                      (inst_jr|inst_jalr) ? uprdata1 :
                      (inst_beq|inst_bne|inst_bgez|inst_bgtz|inst_blez|inst_bltz| inst_bgezal|inst_bltzal) 
                      ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :
                      32'b0;

    assign br_bus = {
        br_e,
        br_addr
    };
    


endmodule
