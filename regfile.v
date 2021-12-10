`include "defines.vh"
module regfile(
    input wire clk,
    input wire rst,
    input wire [4:0] raddr1, //��һ�����Ĵ��� �˿� Ҫ��ȡ�ļĴ����ĵ�ַ
    output wire [31:0] rdata1,//��һ�����Ĵ��� �˿� ����ļĴ���ֵ 
    input wire [4:0] raddr2,
    output wire [31:0] rdata2,
    
    input wire we, //дʹ���ź�
    input wire [4:0] waddr, //Ҫд��ļĴ�����ַ
    input wire [31:0] wdata, //Ҫд�������
    input wire hiwe,
    input wire lowe,
    input wire hir,
    input wire lor,
    input wire [31:0] hi_i,
    input wire [31:0] lo_i,
    output wire [31:0] hilodata
);
    reg [31:0] reg_array [31:0]; //����32��32λ�Ĵ���
    reg [31:0] HI;
    reg [31:0] LO;
    // д�˿�
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
    
    // ���˿�1
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : reg_array[raddr1];

    // ���˿�2
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : reg_array[raddr2];
endmodule