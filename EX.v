`include "lib/defines.vh"
module EX(
    input wire clk,
    input wire rst,
    input wire [`StallBus-1:0] stall,

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,
    
    output wire data_sram_en,
    output wire [3:0] data_sram_wen,
    output wire [31:0] data_sram_addr, //内存地址
    output wire [31:0] data_sram_wdata, //写的数据值
    output wire is_lw,
    output wire ex_id_we,
    output wire stallreq_for_ex,
    output wire [65:0] ex_hilo
);

    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;
 
//	assign excepttype_o = {excepttype_i[31:12],ovassert,trapassert,excepttype_i[9:8],8'h00};
//	assign current_inst_address_o = current_inst_address_i;
    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end

        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus;
        end
    end

    wire [31:0] ex_pc, inst;
    wire [11:0] alu_op;
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire data_ram_en;
    wire data_ram_wen;
    wire [3:0] sl;
    wire rf_we;
    wire [4:0] rf_waddr;  //指令执行写入的目的寄存器地址
    wire sel_rf_res;
    wire [31:0] rf_rdata1, rf_rdata2;
    reg is_in_delayslot;//延迟槽

    wire inst_div,inst_divu,inst_mult,inst_multu,inst_mthi,inst_mtlo;
    wire is_lsa;
    assign {
 
        inst_div,
        inst_divu,
        inst_mult,
        inst_multu,
        inst_mthi,
        inst_mtlo,
        ex_pc,          // 155:124
        inst,           // 123:92
        alu_op,         // 91:80
        sel_alu_src1,   // 
        sel_alu_src2,   // 
        sl,
        data_ram_en,    // 72
        data_ram_wen,   // 71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rf_rdata1,         // 63:32
        rf_rdata2          // 31:0
    } = id_to_ex_bus_r;

    
    ///////////
    assign is_lw = (inst[31:26] == 6'b100011);
    assign is_lsa = (inst[31:26] == 6'b01_1100&&inst[5:0]==6'b11_0111);
    assign ex_id_we =(is_lw?1'b0:rf_we);
    
    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    wire [1:0]sa,sa1;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]};
    assign imm_zero_extend = {16'b0, inst[15:0]};
    assign sa_zero_extend = {27'b0,inst[10:6]};
  

    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : 
                      (is_lsa &inst[7:6]==2'b11) ? {rf_rdata1[27:0] ,4'b0}
                    :(is_lsa & inst[7:6]==2'b10) ? {rf_rdata1[28:0] ,3'b0}
                    :(is_lsa & inst[7:6]==2'b01) ? {rf_rdata1[29:0] ,2'b0}
                    :(is_lsa & inst[7:6]==2'b00) ? {rf_rdata1[30:0] ,1'b0}
                    :rf_rdata1;
                      

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend :
         
                       rf_rdata2
                      ;
    
    
    alu u_alu(
    	.alu_control (alu_op      ),
        .alu_src1    (alu_src1    ),
        .alu_src2    (alu_src2    ),
        .alu_result  (alu_result  )
    );

    assign ex_result = alu_result ;
    assign data_sram_addr = ex_result;
    ///////////////
    
    assign data_sram_en = data_ram_en;
    ///////////
    assign data_sram_wen =   (sl==4'b0111 && ex_result[1:0] == 2'b00 &&data_ram_wen == 1'b1)? 4'b0001 
                            :(sl==4'b0111 && ex_result[1:0] == 2'b01 &&data_ram_wen == 1'b1)? 4'b0010
                            :(sl==4'b0111 && ex_result[1:0] == 2'b10 &&data_ram_wen == 1'b1)? 4'b0100
                            :(sl==4'b0111 && ex_result[1:0] == 2'b11 &&data_ram_wen == 1'b1)? 4'b1000
                            :(sl==4'b1000 && ex_result[1:0] == 2'b00 &&data_ram_wen == 1'b1)? 4'b0011
                            :(sl==4'b1000 && ex_result[1:0]== 2'b10 &&data_ram_wen == 1'b1)? 4'b1100
                            :(sl==4'b0010&&data_ram_wen == 1'b1)  ? 4'b1111
                            : 4'b0000; 
    assign data_sram_wdata =(data_sram_wen==4'b1111) ? rf_rdata2 
                            :(data_sram_wen==4'b0001) ? {24'b0,rf_rdata2[7:0]}
                            :(data_sram_wen==4'b0010) ? {16'b0,rf_rdata2[7:0],8'b0}
                            :(data_sram_wen==4'b0100) ? {8'b0,rf_rdata2[7:0],16'b0}
                            :(data_sram_wen==4'b1000) ? {rf_rdata2[7:0],24'b0}
                            :(data_sram_wen==4'b0011) ? {16'b0,rf_rdata2[15:0]}
                            :(data_sram_wen==4'b1100) ? {rf_rdata2[15:0],16'b0}
                            :32'b0;
    ///////////////
    assign ex_to_mem_bus = {
        sl,    
        ex_pc,          
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };
    // MUL part
    wire [63:0] mul_result;
    wire mul_signed; // 有符号乘法标记
    wire [31:0] muldata1;
    wire [31:0] muldata2;
    assign mul_signed =inst_mult?1:0;
    assign muldata1 =(inst_mult|inst_multu)?rf_rdata1:32'b0;
    assign muldata2 =(inst_mult|inst_multu)?rf_rdata2:32'b0;
//    mul u_mul(
//    	.clk        (clk            ),
//        .resetn     (~rst           ),
//        .mul_signed (mul_signed     ),
//        .ina        (muldata1       ), // 乘法源操作数1
//        .inb        (muldata2       ), // 乘法源操作数2
//        .result     (mul_result     ) // 乘法结果 64bit
//    );

   
    // DIV part
    wire [63:0] div_result;
   // wire inst_div, inst_divu; //inst_div为有符号除 inst_divu无符号
    wire div_ready_i, mul_ready_i;
    reg stallreq_for_div, stallreq_for_mul;
    assign stallreq_for_ex = stallreq_for_div| stallreq_for_mul;

    reg [31:0] div_opdata1_o; //被除数
    reg [31:0] div_opdata2_o; //除数
    reg div_start_o;
    reg signed_div_o; //是否是有符号除法

    reg [31:0] mul_opdata1_o; //被乘数
    reg [31:0] mul_opdata2_o; //乘数
    reg mul_start_o;
    reg signed_mul_o; //是否是有符号乘法
    
    mymul u_mul(
    	.clk        (clk            ),
        .rst        (rst            ),
        .mul_signed (signed_mul_o   ),
        .ina        (mul_opdata1_o  ), // 乘法源操作数1
        .inb        (mul_opdata2_o  ), // 乘法源操作数2
        .start_i    (mul_start_o    ),
        .result_o   (mul_result     ), // 乘法结果 64bit
        .ready_o    (mul_ready_i    )
    );
    
    div u_div(
    	.rst          (rst              ),  //复位
        .clk          (clk              ),  //时钟
        .signed_div_i (signed_div_o     ),  //是否为有符号除法运算，1位有符号
        .opdata1_i    (div_opdata1_o    ),  //被除数
        .opdata2_i    (div_opdata2_o    ),  //除数
        .start_i      (div_start_o      ),  //是否开始除法运算
        .annul_i      (1'b0             ),  //是否取消除法运算，1位取消
        .result_o     (div_result       ),  // 除法结果 64bit
        .ready_o      (div_ready_i      )   // 除法是否结束
    );

    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end
    
    always @ (*) begin
        if (rst) begin
            stallreq_for_mul = `NoStop;
            mul_opdata1_o = `ZeroWord;
            mul_opdata2_o = `ZeroWord;
            mul_start_o = `MulStop;
            signed_mul_o = 1'b0;
        end
        else begin
            stallreq_for_mul = `NoStop;
            mul_opdata1_o = `ZeroWord;
            mul_opdata2_o = `ZeroWord;
            mul_start_o = `MulStop;
            signed_mul_o = 1'b0;
            case ({inst_mult,inst_multu})
                2'b10:begin
                    if (mul_ready_i == `MulResultNotReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStart;
                        signed_mul_o = 1'b1;
                        stallreq_for_mul = `Stop;
                    end
                    else if (mul_ready_i == `MulResultReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b1;
                        stallreq_for_mul = `NoStop;
                    end
                    else begin
                        mul_opdata1_o = `ZeroWord;
                        mul_opdata2_o = `ZeroWord;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `NoStop;
                    end
                end
                2'b01:begin
                    if (mul_ready_i == `MulResultNotReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStart;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `Stop;
                    end
                    else if (mul_ready_i == `MulResultReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `NoStop;
                    end
                    else begin
                        mul_opdata1_o = `ZeroWord;
                        mul_opdata2_o = `ZeroWord;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end
    // mul_result 和 div_result 可以直接使用


    wire hiwe,lowe;
    wire [31:0]hidata;
    wire [31:0]lodata;
    assign hiwe =inst_mthi|inst_mult|inst_multu|inst_div|inst_divu;
    assign lowe =inst_mtlo|inst_mult|inst_multu|inst_div|inst_divu;
    assign hidata =(inst_div|inst_divu)?div_result[63:32]:
                   (inst_mult|inst_multu)?mul_result[63:32]:
                   inst_mthi?rf_rdata1:
                   32'b0;
    assign lodata =(inst_div|inst_divu)?div_result[31:0]:
                   (inst_mult|inst_multu)?mul_result[31:0]:
                   inst_mtlo?rf_rdata1:
                   32'b0;
    assign ex_hilo ={
        hiwe,
        lowe,
        hidata,
        lodata
        };
     
        
endmodule


