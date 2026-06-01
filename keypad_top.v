module keypad_top(
    input clk,
    input [3:0] cols,
    output reg [3:0] rows,
    output [3:0] leds,
    output special_led,
    output reg [6:0] SSeg,
    output reg [3:0] an,
    output reg led_ok,
    output reg led_fail,
    output reg pwm
);
 
    reg [3:0] led_data = 0;
    reg special = 0;
    assign leds        = ~led_data;
    assign special_led = ~special;
 
    //------------------------------------------------
    // CONTRASEÑA
    //------------------------------------------------
    parameter CLAVE_3 = 4'd1;
    parameter CLAVE_2 = 4'd2;
    parameter CLAVE_1 = 4'd3;
    parameter CLAVE_0 = 4'd4;
 
    reg [3:0] digito [0:3];
    reg [2:0] count = 0;
    reg correct = 0;
 
    //------------------------------------------------
    // MODO DISPLAY
    // 0 = normal (muestra dígitos)
    // 1 = mostrar "OKEY"
    // 2 = mostrar "FAIL"
    //------------------------------------------------
    reg [1:0] display_mode = 0;
 
    initial begin
        digito[0]    = 4'hF;
        digito[1]    = 4'hF;
        digito[2]    = 4'hF;
        digito[3]    = 4'hF;
        count        = 0;
        led_ok       = 1;
        led_fail     = 1;
        correct      = 0;
        display_mode = 0;
    end
 
    //------------------------------------------------
    // DIVISOR
    //------------------------------------------------
    reg [19:0] div_counter = 0;
    always @(posedge clk)
        div_counter <= div_counter + 1;
 
    //------------------------------------------------
    // ESCANEO DE FILAS
    //------------------------------------------------
    reg [1:0] scan_row     = 0;
    reg [1:0] scan_phase   = 0;
    reg [3:0] sampled_cols = 4'b1111;
    reg       blocked      = 0;
    reg [6:0] block_timer  = 0;
 
    function is_single_key;
        input [3:0] c;
        case(c)
            4'b1110, 4'b1101, 4'b1011, 4'b0111: is_single_key = 1'b1;
            default: is_single_key = 1'b0;
        endcase
    endfunction
 
    always @(*)
        case(scan_row)
            2'd0: rows = 4'b1110;
            2'd1: rows = 4'b1101;
            2'd2: rows = 4'b1011;
            2'd3: rows = 4'b0111;
        endcase
 
    //------------------------------------------------
    // FSM SCAN + DEBOUNCE + DETECCIÓN
    //
    // Tecla A = fila 0 (scan_row==0), columna 4 (cols==4'b0111)
    // Comportamiento:
    //   - Dígitos numéricos: se acumulan hasta 4, luego el display
    //     queda fijo y NO acepta más números.
    //   - Tecla A con count==4: valida la contraseña y muestra OKEY/FAIL.
    //   - Tecla A con count<4:  ignorada (no hay 4 dígitos aún).
    //   - Estando en OKEY/FAIL: cualquier tecla limpia y reinicia.
    //------------------------------------------------
    always @(posedge div_counter[17]) begin
        scan_phase <= scan_phase + 1;
 
        if(blocked) begin
            if(block_timer == 7'd127) begin
                blocked     <= 0;
                block_timer <= 0;
            end else
                block_timer <= block_timer + 1;
        end
 
        case(scan_phase)
            2'd0: begin end
 
            2'd1: sampled_cols <= cols;
 
            2'd2: begin
                if(cols == sampled_cols && is_single_key(sampled_cols) && !blocked)
                begin
                    blocked     <= 1;
                    block_timer <= 0;
                    special     <= 0;
 
                    // ---- Estamos en OKEY o FAIL: cualquier tecla limpia ----
                    if(display_mode != 0) begin
                        display_mode <= 0;
                        led_ok       <= 1;
                        led_fail     <= 1;
                        correct      <= 0;
                        count        <= 0;
                        digito[0]    <= 4'hF;
                        digito[1]    <= 4'hF;
                        digito[2]    <= 4'hF;
                        digito[3]    <= 4'hF;
                        // la tecla pulsada solo limpia, no se registra
                    end
                    else begin
                        // ---- Tecla A (fila 0, col 4'b0111): validar ----
                        if(scan_row == 2'd0 && sampled_cols == 4'b0111) begin
                            special <= 1;
                            if(count == 4) begin
                                // Comparar los 4 dígitos con la contraseña
                                if(digito[3]==CLAVE_3 && digito[2]==CLAVE_2 &&
                                   digito[1]==CLAVE_1 && digito[0]==CLAVE_0)
                                begin
                                    led_ok   <= 0;
                                    led_fail <= 1;
                                    correct  <= 1;
                                    display_mode <= 1;  // OKEY
                                end else begin
                                    led_ok   <= 1;
                                    led_fail <= 0;
                                    correct  <= 0;
                                    display_mode <= 2;  // FAIL
                                end
                            end
                            // Si count < 4 la tecla A se ignora (no hay 4 dígitos)
                        end
 
                        // ---- Tecla B (fila 1, col 4'b0111): borrar último dígito ----
                        else if(scan_row == 2'd1 && sampled_cols == 4'b0111) begin
                            special <= 1;
                            if(count > 0) begin
                                // Shift derecha: descarta digito[0] y mete F en la izquierda
                                digito[0] <= digito[1];
                                digito[1] <= digito[2];
                                digito[2] <= digito[3];
                                digito[3] <= 4'hF;
                                count     <= count - 1;
                            end
                            // Si count==0 no hay nada que borrar, se ignora
                        end
 
                        // ---- Teclas numéricas: solo si count < 4 ----
                        else if(count < 4) begin
                            led_ok   <= 1;
                            led_fail <= 1;
                            case(scan_row)
                                2'd0: case(sampled_cols)
                                    4'b1110: begin led_data<=4'd1; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd1; count<=count+1; end
                                    4'b1101: begin led_data<=4'd2; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd2; count<=count+1; end
                                    4'b1011: begin led_data<=4'd3; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd3; count<=count+1; end
                                    // 4'b0111 ya fue capturado arriba como tecla A
                                endcase
                                2'd1: case(sampled_cols)
                                    4'b1110: begin led_data<=4'd4; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd4; count<=count+1; end
                                    4'b1101: begin led_data<=4'd5; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd5; count<=count+1; end
                                    4'b1011: begin led_data<=4'd6; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd6; count<=count+1; end
                                    // 4'b0111 = tecla B, ya capturada arriba
                                endcase
                                2'd2: case(sampled_cols)
                                    4'b1110: begin led_data<=4'd7; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd7; count<=count+1; end
                                    4'b1101: begin led_data<=4'd8; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd8; count<=count+1; end
                                    4'b1011: begin led_data<=4'd9; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd9; count<=count+1; end
                                    4'b0111: special<=1;  // tecla C — ignorada
                                endcase
                                2'd3: case(sampled_cols)
                                    4'b1101: begin led_data<=4'd0; digito[3]<=digito[2]; digito[2]<=digito[1]; digito[1]<=digito[0]; digito[0]<=4'd0; count<=count+1; end
                                    4'b1110,4'b1011,4'b0111: special<=1;  // *, #, D — ignoradas
                                endcase
                            endcase
                        end
                        // count==4 y no es tecla A → ignorar pulsación numérica
 
                    end
                end
            end
 
            2'd3: scan_row <= scan_row + 1;
        endcase
    end
 
    //------------------------------------------------
    // SINCRONIZADOR
    //------------------------------------------------
    reg correct_s1 = 0;
    reg correct_s2 = 0;
 
    always @(posedge clk) begin
        correct_s1 <= correct;
        correct_s2 <= correct_s1;
    end
 
    //------------------------------------------------
    // SERVO PWM
    //------------------------------------------------
    localparam PERIODO  = 1_000_000;
    localparam TON_MIN  = 25_000;
    localparam TON_PASO = 6_667;
 
    reg [19:0] contador = 0;
    reg [19:0] ton      = TON_MIN;
 
    always @(posedge clk)
        ton <= correct_s2 ? TON_MIN + (20'd15 * TON_PASO) : TON_MIN;
 
    always @(posedge clk) begin
        if(contador >= PERIODO - 1)
            contador <= 20'd0;
        else
            contador <= contador + 20'd1;
    end
 
    always @(posedge clk)
        pwm <= (contador < ton) ? 1'b1 : 1'b0;
 
    //------------------------------------------------
    // MULTIPLEXACIÓN 4 DISPLAYS
    //------------------------------------------------
    reg [15:0] mux_counter = 0;
    reg [1:0]  disp_sel    = 0;
 
    always @(posedge clk)
        mux_counter <= mux_counter + 1;
 
    always @(posedge mux_counter[14])
        disp_sel <= disp_sel + 1;
 
    //------------------------------------------------
    // 7 SEGMENTOS — caracteres especiales
    // Activo bajo, segmentos: gfedcba
    //
    //   CHAR_NORMAL = 3'd0  → decodifica BCD
    //   CHAR_O      = 3'd1  → 1000000
    //   CHAR_K      = 3'd2  → 0001001
    //   CHAR_E      = 3'd3  → 0000110
    //   CHAR_Y      = 3'd4  → 0010001
    //   CHAR_F      = 3'd5  → 0001110
    //   CHAR_A      = 3'd6  → 0001000
    //   CHAR_I      = 3'd7  → 1111001  (igual que 1, solo segmentos b y c)
    //   CHAR_L      = 3'd8  → 1000111
    //
    // Nota: CHAR_I usa el mismo patrón que el dígito 1 (solo b y c encendidos)
    //------------------------------------------------
 
    localparam CHAR_NORMAL = 4'd0;
    localparam CHAR_O      = 4'd1;
    localparam CHAR_K      = 4'd2;
    localparam CHAR_E      = 4'd3;
    localparam CHAR_Y      = 4'd4;
    localparam CHAR_F      = 4'd5;
    localparam CHAR_A      = 4'd6;
    localparam CHAR_I      = 4'd7;
    localparam CHAR_L      = 4'd8;
 
    reg [3:0] cur_digit;
    reg       cur_active;
    reg [3:0] cur_char;   // ampliado a 4 bits para soportar 9 caracteres
 
    always @(*) begin
        cur_char   = CHAR_NORMAL;
        cur_digit  = 4'hF;
        cur_active = 1'b0;
 
        case(display_mode)
            // ---- modo normal: muestra dígitos ingresados ----
            2'd0: begin
                case(disp_sel)
                    2'd0: begin cur_digit = digito[3]; cur_active = (count >= 4); end
                    2'd1: begin cur_digit = digito[2]; cur_active = (count >= 3); end
                    2'd2: begin cur_digit = digito[1]; cur_active = (count >= 2); end
                    2'd3: begin cur_digit = digito[0]; cur_active = (count >= 1); end
                endcase
            end
 
            // ---- modo OKEY: muestra O K E Y ----
            // disp_sel: 0=O  1=K  2=E  3=Y
            2'd1: begin
                cur_active = 1'b1;
                case(disp_sel)
                    2'd0: cur_char = CHAR_O;
                    2'd1: cur_char = CHAR_K;
                    2'd2: cur_char = CHAR_E;
                    2'd3: cur_char = CHAR_Y;
                endcase
            end
 
            // ---- modo FAIL: muestra F A I L ----
            // disp_sel: 0=F  1=A  2=I  3=L
            2'd2: begin
                cur_active = 1'b1;
                case(disp_sel)
                    2'd0: cur_char = CHAR_F;
                    2'd1: cur_char = CHAR_A;
                    2'd2: cur_char = CHAR_I;
                    2'd3: cur_char = CHAR_L;
                endcase
            end
 
            default: begin end
        endcase
    end
 
    always @(*) begin
        case(disp_sel)
            2'd0: an = cur_active ? 4'b0111 : 4'b1111;
            2'd1: an = cur_active ? 4'b1011 : 4'b1111;
            2'd2: an = cur_active ? 4'b1101 : 4'b1111;
            2'd3: an = cur_active ? 4'b1110 : 4'b1111;
        endcase
    end
 
    always @(*) begin
        if(!cur_active) begin
            SSeg = 7'b1111111;
        end else begin
            case(cur_char)
                // Caracteres especiales (activo bajo, orden gfedcba)
                CHAR_O: SSeg = 7'b1000000;  // O  — segmentos a b c d e f
                CHAR_K: SSeg = 7'b0001001;  // K  — segmentos b f g (aproximación)
                CHAR_E: SSeg = 7'b0000110;  // E  — segmentos a f g e d
                CHAR_Y: SSeg = 7'b0010001;  // Y  — segmentos b c f g
                CHAR_F: SSeg = 7'b0001110;  // F  — segmentos a f g e
                CHAR_A: SSeg = 7'b0001000;  // A  — segmentos a b c e f g
                CHAR_I: SSeg = 7'b1111001;  // I  — segmentos b c (igual que dígito 1)
                CHAR_L: SSeg = 7'b1000111;  // L  — segmentos f e d
 
                // CHAR_NORMAL: decodifica cur_digit como BCD
                default: begin
                    case(cur_digit)
                        4'd0: SSeg = 7'b1000000;
                        4'd1: SSeg = 7'b1111001;
                        4'd2: SSeg = 7'b0100100;
                        4'd3: SSeg = 7'b0110000;
                        4'd4: SSeg = 7'b0011001;
                        4'd5: SSeg = 7'b0010010;
                        4'd6: SSeg = 7'b0000010;
                        4'd7: SSeg = 7'b1111000;
                        4'd8: SSeg = 7'b0000000;
                        4'd9: SSeg = 7'b0010000;
                        default: SSeg = 7'b1111111;
                    endcase
                end
            endcase
        end
    end
 
endmodule