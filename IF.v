`include "lib/defines.vh"
module IF(
    input wire clk,
    input wire rst,
    input wire [`StallBus-1:0] stall, //��ͣ

    // input wire flush,
    // input wire [31:0] new_pc,

    input wire [`BR_WD-1:0] br_bus,  //�洢�����ʹ���ź���PC��ַ ת��ָ��ʹ��

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus, //����ce_reg, pc_reg

    output wire inst_sram_en,    //ʹ���ź����
    output wire [3:0] inst_sram_wen,    //���ܿ��Ʒô���
    output wire [31:0] inst_sram_addr,  //ȡָ�׶�ȡ�õ�ָ���Ӧ�ĵ�ַ
    output wire [31:0] inst_sram_wdata  //ȡָ�׶�ȡ�õ�ָ��
);
    reg [31:0] pc_reg;  //Ҫ��ȡ��ָ���ַ
    reg ce_reg;  //ָ��洢��ʹ���ź�
    wire [31:0] next_pc;  //nextPC
    wire br_e;            //�ж�ָ��洢���Ƿ����
    wire [31:0] br_addr;  //ָ��洢��

    assign {
        br_e,
        br_addr
    } = br_bus;          //���﷨��˼�ǰ�λ��ֵ ��������������λ�����

//���PCģ��Ĺ���
//�Ը�λ�źŵ��ж���ִ��
    always @ (posedge clk) begin
        if (rst) begin
            pc_reg <= 32'hbfbf_fffc;
        end
        else if (stall[0]==`NoStop) begin
            pc_reg <= next_pc;
        end
    end
//����ʱ���ź��µ�ִ������ͣ���
    always @ (posedge clk) begin
        if (rst) begin
            ce_reg <= 1'b0;
        end
        else if (stall[0]==`NoStop) begin
            ce_reg <= 1'b1;
        end
    end


    assign next_pc = br_e ? br_addr 
                   : pc_reg + 32'h4;  //һ��ָ��Ϊ4�ֽ�

    
    assign inst_sram_en = ce_reg;
    assign inst_sram_wen = 4'b0;        //��ʼ��
    assign inst_sram_addr = pc_reg;   //ȡ���ĵ�ַ��ΪPC����ĵ�ַ
    assign inst_sram_wdata = 32'b0;   //��ʼ��
    assign if_to_id_bus = {
        ce_reg,
        pc_reg
    };

endmodule