`timescale 1ns / 1ps

// OV7670이 YUV422 (YUYV) 모드로 동작 중
// 바이트 순서: Y0 U0 Y1 V0 Y2 U1 Y3 V1 ...
// 첫 번째 바이트 = Y (밝기), 두 번째 바이트 = U/V (색차, 무시)

module ov7670_capture(
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,

    output reg [7:0]  pixel_data,
    output reg        pixel_valid,
    output reg [16:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] y_val = 8'd0;   // 레벨 보정된 Y값

    // YUV Y 범위 16~235 → 0~255 으로 스트레치
    // (Y - 16) * 1.5 = (Y-16) + (Y-16)/2 → max 219*1.5=329 → clamp 255
    wire [7:0] y_sub    = (d > 8'd16) ? (d - 8'd16) : 8'd0;
    wire [9:0] y_scaled = {2'b0, y_sub} + {3'b0, y_sub[7:1]};  // × 1.5
    wire [7:0] y_adj    = y_scaled[9:8] ? 8'd255 : y_scaled[7:0];

    reg [9:0]  x       = 10'd0;
    reg [8:0]  y       = 9'd0;
    reg        vsync_d = 1'b0;

    // 2x2 평균 필터 (aliasing 저감)
    reg [7:0] y_prev = 8'd0;
    reg [8:0] y_line [0:319];  // 이전 행의 수평 합

    wire [8:0] y_hsum = {1'b0, y_prev} + {1'b0, y_val};

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
                y_val    <= y_adj;      // 첫 번째 바이트 = Y, 레벨 보정 후 저장
                byte_sel <= 1'b1;
            end else begin
                byte_sel <= 1'b0;       // 두 번째 바이트(U/V) 무시

                if (x[0] == 1'b0) begin
                    // 짝수 픽셀: Y 저장
                    y_prev <= y_val;
                end else begin
                    // 홀수 픽셀: 수평 쌍 완성
                    if (y[0] == 1'b0) begin
                        // 짝수 행: line_buf에 저장
                        y_line[x[9:1]] <= y_hsum;
                    end else begin
                        // 홀수 행: 2x2 평균 출력
                        pixel_data  <= ({1'b0, y_line[x[9:1]]} + {1'b0, y_hsum}) >> 2;
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
