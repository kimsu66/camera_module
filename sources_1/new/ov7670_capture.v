`timescale 1ns / 1ps

module ov7670_capture(
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire  [7:0] d,

    output reg  [15:0] pixel_data,
    output reg         pixel_valid,
    output reg  [16:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] low_byte = 8'd0;  // 첫 번째 바이트 = low byte (GGGBBBBB)

    reg [9:0]  x       = 10'd0;
    reg [8:0]  y       = 9'd0;
    reg        vsync_d = 1'b0;

    // RGB565: 첫 번째 바이트 = low byte (GGGBBBBB), 두 번째 = high byte (RRRRRGGG)
    wire [4:0] r5 = d[7:3];
    wire [5:0] g6 = {d[2:0], low_byte[7:5]};
    wire [4:0] b5 = low_byte[4:0];

    // 2x2 평균 필터 - 채널별
    reg [4:0] r_prev = 5'd0;
    reg [5:0] g_prev = 6'd0;
    reg [4:0] b_prev = 5'd0;

    reg [5:0] r_line [0:319];   // 수평 R 합 (6-bit, max 62)
    reg [6:0] g_line [0:319];   // 수평 G 합 (7-bit, max 126)
    reg [5:0] b_line [0:319];   // 수평 B 합 (6-bit, max 62)

    wire [5:0] r_hsum = {1'b0, r_prev} + {1'b0, r5};
    wire [6:0] g_hsum = {1'b0, g_prev} + {1'b0, g6};
    wire [5:0] b_hsum = {1'b0, b_prev} + {1'b0, b5};

    // 2x2 합 >> 2 = 평균
    wire [4:0] r_out = ({1'b0, r_line[x[9:1]]} + {1'b0, r_hsum}) >> 2;
    wire [5:0] g_out = ({1'b0, g_line[x[9:1]]} + {1'b0, g_hsum}) >> 2;
    wire [4:0] b_out = ({1'b0, b_line[x[9:1]]} + {1'b0, b_hsum}) >> 2;

    always @(posedge pclk) begin
        pixel_valid <= 1'b0;
        vsync_d     <= vsync;

        if (vsync && !vsync_d) begin
            x        <= 10'd0;
            y        <= 9'd0;
            byte_sel <= 1'b0;
        end
        else if (!href) begin
            byte_sel <= 1'b0;   // 라인마다 byte 정렬 리셋
        end
        else begin
            if (!byte_sel) begin
                low_byte <= d;
                byte_sel <= 1'b1;
            end else begin
                byte_sel <= 1'b0;

                if (x[0] == 1'b0) begin
                    // 짝수 픽셀: 채널별 이전값 저장
                    r_prev <= r5;
                    g_prev <= g6;
                    b_prev <= b5;
                end else begin
                    // 홀수 픽셀: 수평 쌍 완성
                    if (y[0] == 1'b0) begin
                        // 짝수 행: 수평 합 저장
                        r_line[x[9:1]] <= r_hsum;
                        g_line[x[9:1]] <= g_hsum;
                        b_line[x[9:1]] <= b_hsum;
                    end else begin
                        // 홀수 행: 2x2 평균 출력 → RGB565로 조합
                        pixel_data  <= {r_out, g_out, b_out};
                        pixel_valid <= 1'b1;
                        addr <= ({1'b0, y[8:1], 8'b0}
                               + {3'b0, y[8:1], 6'b0}
                               + {8'b0, x[9:1]});
                    end
                end

                if (x == 10'd639) begin
                    x <= 10'd0;
                    if (y < 9'd479)
                        y <= y + 9'd1;
                end else begin
                    x <= x + 10'd1;
                end
            end
        end
    end

endmodule
