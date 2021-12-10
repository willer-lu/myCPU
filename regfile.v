`include "defines.vh"
module regfile(
    input wire clk,
    input wire rst,
    input wire [4:0] raddr1, //第一个读寄存器 端口 要读取的寄存器的地址
    output wire [31:0] rdata1,//第一个读寄存器 端口 输出的寄存器值 
    input wire [4:0] raddr2,
    output wire [31:0] rdata2,
    
    input wire we, //写使能信号
    input wire [4:0] waddr, //要写入的寄存器地址
    input wire [31:0] wdata, //要写入的数据
    input wire hiwe,
    input wire lowe,
    input wire hir,
    input wire lor,
    input wire [31:0] hi_i,
    input wire [31:0] lo_i,
    output wire [31:0] hilodata
);
    reg [31:0] reg_array [31:0]; //定义32个32位寄存器
    reg [31:0] HI;
    reg [31:0] LO;
    // 写端口
    always @ (posedge clk) begin
        if (we && waddr!=5'b0) begin
            reg_array[waddr] <= wdata;
        end
    end
//    always @ (posedge clk) begin
//		if (rst ) begin
//					HI <= `ZeroWord;
//					LO <= `ZeroWord;
//		end
//	end
	always @ (posedge clk) begin
		if((hiwe == 1'b1)) begin
					HI <= hi_i;
		end
	end
	always @ (posedge clk) begin
		 if((lowe == 1'b1)) begin
					LO <= lo_i;
		end
	end
    assign hilodata = (hir)?HI:(lor)?LO:32'b0;
    
    // 读端口1
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : reg_array[raddr1];

    // 读端口2
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : reg_array[raddr2];
endmodule