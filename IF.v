`include "lib/defines.vh"
module IF(
    input wire clk,
    input wire rst,
    input wire [`StallBus-1:0] stall, //暂停


    input wire [`BR_WD-1:0] br_bus,  //存储输入的使能信号与PC地址 转移指令使用

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus, //储存ce_reg, pc_reg

    output wire inst_sram_en,    //使能信号输出
    output wire [3:0] inst_sram_wen,    //控制访存用
    output wire [31:0] inst_sram_addr,  //取指阶段取得的指令对应的地址
    output wire [31:0] inst_sram_wdata  //取指阶段取得的指令
);
    reg [31:0] pc_reg;  //要读取的指令地址
    reg ce_reg;  //指令存储器使能信号
    wire [31:0] next_pc;  //nextPC
    wire br_e;            //判断指令存储器是否可用
    wire [31:0] br_addr;  

    assign {
        br_e,
        br_addr
    } = br_bus;          //该语法意思是按位赋值 括号内与括号外位长相等

//完成PC模块的功能
//对复位信号的判断与执行
    always @ (posedge clk) begin
        if (rst) begin
            pc_reg <= 32'hbfbf_fffc;

            end else if (stall[0]==`NoStop) begin
                pc_reg <= next_pc;
            end
        end
   
//正常时钟信号下的执行与暂停情况
    always @ (posedge clk) begin
        if (rst ) begin
            ce_reg <= 1'b0;
        end
        else if (stall[0]==`NoStop) begin
            ce_reg <= 1'b1;
        end
    end


    assign next_pc = br_e ? br_addr 
                   : pc_reg + 32'h4;  //一条指令为4字节

    
    assign inst_sram_en = ce_reg;
    assign inst_sram_wen = 4'b0;        //初始化
    assign inst_sram_addr = pc_reg;   //将指令存储的地址和使能信号传递给存储器来取出指令内容
    assign inst_sram_wdata = 32'b0;   //初始化
    assign if_to_id_bus = {
        ce_reg,
        pc_reg
    };

endmodule
