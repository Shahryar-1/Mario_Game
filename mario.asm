; ============================================================================
;  SUPER MARIO ENGINE   -   EL2003 COAL Semester Project
;  16-bit x86 Real Mode, NASM Assembler, VGA Mode 13h (320x200x256)
;  Target Output: MARIO.COM (DOS executable format)
;
;  Build Instruction:
;      nasm -f bin mario.asm -o MARIO.COM
;
;  Run Instruction:
;      In DOSBox: mount c . -> c: -> MARIO.COM
;
;  Two-File Structure:
;    File 1: mario.asm (Engine, main game loop, interrupts, physics, rendering)
;    File 2: data.asm  (Variables, level map, palettes, and sprite artwork)
;    Linked via #include / %include "data.asm"
;
;  Controls:
;    Left / Right Arrow : Walk
;    Left Shift         : Run (increases max speed)
;    Spacebar           : Jump (variable height based on hold duration)
;    P                  : Pause / Unpause
;    ESC                : Exit to DOS
;    Debug Keys: F1 = 5s Time Left, F2 = 99 Coins, F3 = Palette Test Screen
; ============================================================================
cpu 8086
bits 16
org 100h


; ############################################################################
; ## constants.inc
; ############################################################################
; ============================================================================
; constants.inc  -  Named constants for SUPER MARIO ENGINE (Module 1)
; All numbers come from the project manual (Appendix A and Section 5).
; ============================================================================

; ---- Display and tile geometry (A.1) ---------------------------------------
SCREEN_W        equ 320             ; Mode 13h width in pixels
SCREEN_H        equ 200             ; Mode 13h height in pixels
MAP_PIXEL_H     equ 192             ; 12 rows * 16 px (bottom 8 px stay black)
TILE_SIZE       equ 16              ; tile / sprite edge in pixels
LEVEL_COLS      equ 60              ; level width in tiles
LEVEL_ROWS      equ 12              ; level height in tiles
LEVEL_BYTES     equ LEVEL_COLS*LEVEL_ROWS
LEVEL_PIXELS    equ LEVEL_COLS*TILE_SIZE   ; 960
MAX_CAMERA      equ LEVEL_PIXELS-SCREEN_W  ; 640
MAX_HERO_X      equ LEVEL_PIXELS-TILE_SIZE ; 944 = right end of the level
START_X         equ 32              ; Mario start x (world)
START_FEET_Y    equ 160             ; feet y when standing on row 9
FRAME_BYTES     equ 64000

; ---- Palette indices (set up in SetPalette) --------------------------------
C_BLACK         equ 0               ; also "transparent" inside sprites
C_SKY           equ 1
C_RED           equ 2
C_BLUE          equ 3
C_SKIN          equ 4
C_BROWN         equ 5
C_BRICK         equ 6
C_GRASS         equ 7
C_DGREEN        equ 8
C_WHITE         equ 9
C_YELLOW        equ 10
C_TAN           equ 11
C_ORANGE        equ 12
C_DBROWN        equ 13
C_PIPE          equ 14
C_GRAY          equ 15

; ---- Tile codes (A.2) --------------------------------------------------------
T_SKY           equ 0
T_GROUND        equ 1
T_BRICK         equ 2
T_QCOIN         equ 3
T_QMUSH         equ 4
T_EMPTY         equ 5
T_PIPE_TL       equ 6
T_PIPE_TR       equ 7
T_PIPE_BL       equ 8
T_PIPE_BR       equ 9
T_STAIR         equ 10
T_COIN          equ 11
T_FLAG          equ 12

; ---- Scan codes (A.3) --------------------------------------------------------
SC_ESC          equ 01h
SC_P            equ 19h
SC_ENTER        equ 1Ch
SC_LSHIFT       equ 2Ah
SC_SPACE        equ 39h
SC_UP           equ 48h
SC_LEFT         equ 4Bh
SC_RIGHT        equ 4Dh
SC_DOWN         equ 50h
SC_F1           equ 3Bh             ; debug: time left = 5 s
SC_F2           equ 3Ch             ; debug: coins = 99
SC_F3          equ 3Dh             ; debug: colour test screen (title only)

; ---- Game limits (A.4) -------------------------------------------------------
START_LIVES     equ 3
MAX_LIVES       equ 99
LEVEL_TIME      equ 300
MAX_SCORE_HI    equ 000Fh           ; 999,999 = 000F423Fh
MAX_SCORE_LO    equ 423Fh
INVULN_FRAMES   equ 60              ; about 2 s at 30 frames per second
FRAMES_PER_SEC  equ 30
FLAT_FRAMES     equ 30              ; flat Goomba stays about 1 s
KICK_GRACE      equ 8               ; shell ignores Mario for 8 frames
COIN_POP_FRAMES equ 18

; ---- Physics, 8.8 fixed point (A.5) -----------------------------------------
ACCEL           equ 0020h           ; walk acceleration 0.125
FRICTION        equ 0010h           ; 0.0625
BRAKE           equ 0040h           ; braking against the movement
WALK_MAX        equ 0180h           ; 1.5 px/frame
RUN_MAX         equ 0280h           ; 2.5 px/frame
GRAVITY         equ 0042h           ; 0.25
JUMP_START      equ 0FA80h          ; -5.5
JUMP_CUT        equ 0FE00h          ; -2.0
MAX_FALL        equ 0400h           ; 4.0
STOMP_BOUNCE    equ 0FD00h          ; -3.0
STOMP_BOUNCE_HI equ 0FC00h          ; -4.0 when the jump key is held
DEATH_JUMP      equ 0FB10h          ; about -4.9 gives a 48 px hop
GOOMBA_SPEED    equ 0080h
KOOPA_SPEED     equ 00C0h
SHELL_SPEED     equ 0300h
MUSH_SPEED      equ 0103h

; ---- Hero hit-box (inside the 16 px wide sprite) ---------------------------
HB_LEFT         equ 2               ; hit-box x offset from sprite left
HB_RIGHT        equ 13              ; last hit-box pixel
HB_WIDTH        equ 12

; ---- Timer (Module 8) ------------------------------------------------------
PIT_DIVISOR     equ 39774           ; 1193182 / 4 = 30 Hz

; ---- Game states (5.12) ------------------------------------------------------
ST_TITLE        equ 0
ST_PLAYING      equ 1
ST_PAUSED       equ 2
ST_DYING        equ 3
ST_LIFELOST     equ 4
ST_WIN          equ 5
ST_COMPLETE     equ 6
ST_GAMEOVER     equ 7
ST_EXIT         equ 8

; ---- Entity records (5.5): 8 words = 16 bytes each ---------------------------
NUM_ENT         equ 16
ENT_SIZE        equ 16
E_TYPE          equ 0
E_STATE         equ 2
E_X             equ 4               ; world x, whole pixels
E_FRAC          equ 6               ; x fraction (low byte)
E_Y             equ 8               ; top y of the 16x16 box
E_VY            equ 10              ; whole pixels per frame, signed
E_DIR           equ 12              ; +1 right, -1 left
E_TIMER         equ 14

ET_NONE         equ 0
ET_GOOMBA       equ 1
ET_KOOPA        equ 2
ET_SHELL        equ 3
ET_MUSH         equ 4
ET_COIN         equ 5               ; coin popping out of a block (visual)

ES_WAIT         equ 0
ES_WALK         equ 1
ES_FLAT         equ 2
ES_STILL        equ 3
ES_SLIDE        equ 4

; ---- Sprite draw flags ---------------------------------------------------------
SF_MIRROR       equ 1               ; flip horizontally (facing left)
SF_TALL         equ 2               ; 16 x 32 instead of 16 x 16


; ---- Small helper macros for calls with stack parameters (they use AX) -----
%macro TEXT 5                       ; x, y, string, colour, scale
    mov ax, %1
    push ax
    mov ax, %2
    push ax
    mov ax, %3
    push ax
    mov ax, %4
    push ax
    mov ax, %5
    push ax
    call DrawText
%endmacro

%macro NUMBER 7                     ; x, y, low word, high word, digits, colour, scale
    mov ax, %1
    push ax
    mov ax, %2
    push ax
    mov ax, %3
    push ax
    mov ax, %4
    push ax
    mov ax, %5
    push ax
    mov ax, %6
    push ax
    mov ax, %7
    push ax
    call DrawNumber
%endmacro

%define SC_F3 3Dh                   ; debug key: colour test screen

; ============================================================================
; Entry point: set everything up, run the state machine, exit cleanly
; ============================================================================
start:
    cld
    call AllocFrameBuffer           ; second segment for the frame buffer
    jc no_memory
    call ConvertArt                 ; letters -> colour indices
    call ConvertLevel               ; text level -> tile codes
    call SetVideoMode13
    call SetPalette
    call InitFont
    mov word [state], ST_TITLE
    mov word [menu_sel], 0
    call InstallHooks               ; keyboard + timer interrupts
    call ClearHits

main_loop:
    call WaitTick                   ; one frame per timer tick
    inc word [frame_cnt]
    mov bx, [state]
    cmp bx, ST_EXIT
    jae quit
    shl bx, 1
    call word [state_table + bx]    ; jump table indexed by the state number
    jmp short main_loop
quit:
    call Shutdown                   ; never returns

no_memory:
    mov dx, msg_nomem
    mov ah, 9
    int 21h
    mov ax, 4C01h
    int 21h

msg_nomem   db "Not enough memory for the frame buffer.", 13, 10, "$"

state_table dw StateTitle, StatePlaying, StatePaused, StateDying
            dw StateLifeLost, StateWin, StateComplete, StateGameOver


; ############################################################################
; ## gfx.inc
; ############################################################################
; ============================================================================
; gfx.inc  -  Video, frame buffer, drawing primitives, tiles, map, text
; (Modules 2, 3, 4, 5, 6 and the text part of 13)
;
; Calling convention used everywhere: arguments are pushed left to right,
; the callee removes them with "ret N". Every procedure preserves every
; register it does not return (the result, when there is one, is in AX).
; All drawing goes to the OFF-SCREEN frame buffer (segment fb_seg), never
; straight to the screen, except FlipFrame which copies it to A000h.
; ============================================================================

; ----------------------------------------------------------------------------
; SetVideoMode13 / SetTextMode
; Purpose : switch the display with BIOS INT 10h.
; Inputs  : none        Outputs: none        Registers changed: none
; ----------------------------------------------------------------------------
SetVideoMode13:
    push ax
    mov ax, 0013h
    int 10h
    pop ax
    ret

SetTextMode:
    push ax
    mov ax, 0003h
    int 10h
    pop ax
    ret

; ----------------------------------------------------------------------------
; SetPalette
; Purpose : load our 16 game colours into VGA DAC registers 0..15
;           (INT 10h AX=1012h, table of 6-bit R,G,B triplets).
; Registers changed: none
; ----------------------------------------------------------------------------
SetPalette:
    push ax
    push bx
    push cx
    push dx
    push es
    push cs
    pop es
    mov ax, 1012h
    xor bx, bx                      ; first register = 0
    mov cx, 16                      ; sixteen colours
    mov dx, palette_data
    int 10h
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; AllocFrameBuffer
; Purpose : reserve a SECOND 64000-byte segment for the frame buffer.
;           1) INT 21h AH=4Ah shrinks our memory block to 64 KB,
;           2) INT 21h AH=48h allocates 4000 paragraphs above it.
; Outputs : fb_seg = segment address, CF set if DOS refused.
; ----------------------------------------------------------------------------
AllocFrameBuffer:
    push ax
    push bx
    push es
    push cs
    pop es                          ; ES = our PSP segment
    mov ah, 4Ah
    mov bx, 1000h                   ; 1000h paragraphs = 64 KB
    int 21h
    mov ah, 48h
    mov bx, 0FA0h                   ; 4000 paragraphs = 64000 bytes
    int 21h
    jc .fail
    mov [fb_seg], ax
    clc
    jmp short .done
.fail:
    stc
.done:
    pop es
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; ConvertArt
; Purpose : the artwork is typed as letters (art.inc). Replace every letter by
;           its VGA colour index using the (letter, colour) table art_charmap.
; Registers changed: none
; ----------------------------------------------------------------------------
ConvertArt:
    push ax
    push bx
    push cx
    push si
    mov si, art_start
    mov cx, art_end - art_start
.next:
    mov al, [si]
    mov bx, art_charmap
.find:
    cmp byte [bx], 0
    je .nomatch                     ; letter not in the table -> colour 0
    cmp al, [bx]
    je .match
    add bx, 2
    jmp short .find
.match:
    mov al, [bx+1]
    jmp short .store
.nomatch:
    xor al, al
.store:
    mov [si], al
    inc si
    loop .next
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; ConvertLevel
; Purpose : turn the readable text level (level_text) into tile codes in
;           level_orig using the legend table. level_orig is never changed
;           again; level_work is the copy the game modifies.
; Registers changed: none
; ----------------------------------------------------------------------------
ConvertLevel:
    push ax
    push bx
    push cx
    push si
    push di
    mov si, level_text
    mov di, level_orig
    mov cx, LEVEL_BYTES
.next:
    mov al, [si]
    inc si
    mov bx, level_legend
.find:
    cmp byte [bx], 0
    je .nomatch
    cmp al, [bx]
    je .match
    add bx, 2
    jmp short .find
.match:
    mov al, [bx+1]
    jmp short .store
.nomatch:
    xor al, al
.store:
    mov [di], al
    inc di
    loop .next
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; ResetMap
; Purpose : restore the working map from the original with one block move.
; Registers changed: none
; ----------------------------------------------------------------------------
ResetMap:
    push cx
    push si
    push di
    push es
    push cs
    pop es
    cld
    mov si, level_orig
    mov di, level_work
    mov cx, LEVEL_BYTES / 2
    rep movsw
    pop es
    pop di
    pop si
    pop cx
    ret

; ----------------------------------------------------------------------------
; ClearFrame
; Purpose : start of every frame: sky colour for the 192 map rows, black for
;           the bottom 8 rows. Uses REP STOSW (no pixel loop).
; Registers changed: none
; ----------------------------------------------------------------------------
ClearFrame:
    push ax
    push cx
    push di
    push es
    mov es, [fb_seg]
    cld
    xor di, di
    mov ax, (C_SKY << 8) | C_SKY
    mov cx, MAP_PIXEL_H * (SCREEN_W / 2)
    rep stosw
    xor ax, ax
    mov cx, (SCREEN_H - MAP_PIXEL_H) * (SCREEN_W / 2)
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; ClearFrameBlack - whole frame black (used by the text screens).
; ----------------------------------------------------------------------------
ClearFrameBlack:
    push ax
    push cx
    push di
    push es
    mov es, [fb_seg]
    cld
    xor di, di
    xor ax, ax
    mov cx, FRAME_BYTES / 2
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; FlipFrame
; Purpose : copy the finished frame to video memory (A000h) with ONE
;           REP MOVSW, once per timer tick.
; Registers changed: none
; ----------------------------------------------------------------------------
FlipFrame:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, [fb_seg]
    mov ds, ax                      ; source = frame buffer
    mov ax, 0A000h
    mov es, ax                      ; destination = video memory
    xor si, si
    xor di, di
    mov cx, FRAME_BYTES / 2
    cld
    rep movsw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; PutPixel(x, y, colour)            args pushed in this order
; Purpose : plot one pixel in the frame buffer, offset = y*256 + y*64 + x.
;           Pixels outside the screen are ignored.
; Registers changed: none
; ----------------------------------------------------------------------------
PutPixel:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push di
    push es
    mov ax, [bp+8]                  ; x
    cmp ax, SCREEN_W
    jae .out                        ; unsigned test also catches negatives
    mov bx, [bp+6]                  ; y
    cmp bx, SCREEN_H
    jae .out
    mov di, bx
    mov cl, 8
    shl di, cl                      ; y * 256
    mov cl, 6
    shl bx, cl                      ; y * 64
    add di, bx
    add di, ax                      ; + x
    mov es, [fb_seg]
    mov al, [bp+4]
    mov [es:di], al
.out:
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6

; ----------------------------------------------------------------------------
; FillRect(x, y, w, h, colour)
; Purpose : solid rectangle in the frame buffer, clipped to the screen.
; Registers changed: none
; ----------------------------------------------------------------------------
FillRect:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov ax, [bp+12]                 ; x
    mov bx, [bp+10]                 ; y
    mov cx, [bp+8]                  ; w
    mov dx, [bp+6]                  ; h
    test ax, ax
    jge .xok
    add cx, ax                      ; clip left: w += x
    xor ax, ax
.xok:
    test bx, bx
    jge .yok
    add dx, bx                      ; clip top: h += y
    xor bx, bx
.yok:
    mov di, SCREEN_W
    sub di, ax                      ; room to the right edge
    cmp cx, di
    jle .wok
    mov cx, di
.wok:
    mov di, SCREEN_H
    sub di, bx
    cmp dx, di
    jle .hok
    mov dx, di
.hok:
    cmp cx, 0
    jle .done
    cmp dx, 0
    jle .done
    mov di, bx
    push cx
    mov cl, 8
    shl di, cl                      ; y * 256
    mov cl, 6
    shl bx, cl                      ; y * 64
    pop cx
    add di, bx
    add di, ax                      ; di = y*320 + x
    mov es, [fb_seg]
    mov al, [bp+4]
    mov ah, al
    cld
.row:
    push cx
    push di
    rep stosb                       ; one row of w pixels
    pop di
    pop cx
    add di, SCREEN_W                ; next row
    dec dx
    jnz .row
.done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 10

; ----------------------------------------------------------------------------
; DrawSprite(x, y, address, flags)
; Purpose : draw a 16x16 (or 16x32 with SF_TALL) sprite whose pixels are
;           colour indices; index 0 is transparent. SF_MIRROR flips it left to
;           right. The sprite is clipped at all four screen edges BEFORE the
;           loops, so memory outside the frame buffer is never touched.
; Registers changed: none
; ----------------------------------------------------------------------------
DrawSprite:
    push bp
    mov bp, sp
    sub sp, 12                      ; locals: -2 h, -4 c0, -6 c1, -8 r0, -10 r1
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov es, [fb_seg]
    mov ax, 16
    test word [bp+4], SF_TALL
    jz .hset
    mov ax, 32
.hset:
    mov [bp-2], ax                  ; sprite height
    xor cx, cx                      ; c0 = max(0, -x)
    mov ax, [bp+10]
    test ax, ax
    jge .c0ok
    neg ax
    mov cx, ax
.c0ok:
    mov [bp-4], cx
    mov ax, SCREEN_W                ; c1 = min(16, 320 - x)
    sub ax, [bp+10]
    cmp ax, 16
    jle .c1ok
    mov ax, 16
.c1ok:
    mov [bp-6], ax
    mov ax, [bp-4]
    cmp ax, [bp-6]
    jl $+5                       ; nothing visible horizontally
    jmp .done
    xor cx, cx                      ; r0 = max(0, -y)
    mov ax, [bp+8]
    test ax, ax
    jge .r0ok
    neg ax
    mov cx, ax
.r0ok:
    mov [bp-8], cx
    mov ax, SCREEN_H                ; r1 = min(h, 200 - y)
    sub ax, [bp+8]
    cmp ax, [bp-2]
    jle .r1ok
    mov ax, [bp-2]
.r1ok:
    mov [bp-10], ax
    mov dx, [bp-8]                  ; DX = current sprite row
.rowloop:
    cmp dx, [bp-10]
    jge .done
    mov ax, [bp+8]
    add ax, dx                      ; screen row = y + r
    mov bx, ax
    mov cl, 8
    shl ax, cl
    mov di, ax                      ; row * 256
    mov cl, 6
    shl bx, cl                      ; row * 64
    add di, bx
    add di, [bp+10]
    add di, [bp-4]                  ; + x + c0
    mov si, dx
    mov cl, 4
    shl si, cl                      ; r * 16
    add si, [bp+6]                  ; + sprite address
    mov cx, [bp-6]
    sub cx, [bp-4]                  ; pixels in this row
    test word [bp+4], SF_MIRROR
    jz .forward
    std                             ; mirrored: read the row backwards
    add si, 15
    sub si, [bp-4]
    jmp short .pix
.forward:
    cld
    add si, [bp-4]
.pix:
    lodsb
    or al, al
    jz .skip                        ; transparent
    mov [es:di], al
.skip:
    inc di
    loop .pix
    cld
    inc dx
    jmp short .rowloop
.done:
    cld
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret 8

; ----------------------------------------------------------------------------
; GetTile(px, py)  ->  AX = tile code at that pixel position of the WORKING map
; Purpose : pixel position to tile code. Outside the map (left/right of the
;           level, above row 0, below row 11) the answer is T_SKY.
; Registers changed: AX only
; ----------------------------------------------------------------------------
GetTile:
    push bp
    mov bp, sp
    push bx
    push cx
    push dx
    mov ax, [bp+6]                  ; px
    cmp ax, LEVEL_PIXELS
    jae .sky
    mov bx, [bp+4]                  ; py
    cmp bx, MAP_PIXEL_H
    jae .sky
    mov cl, 4
    shr ax, cl                      ; column = px / 16
    shr bx, cl                      ; row    = py / 16
    push ax                         ; keep the column
    mov ax, bx
    mov cx, LEVEL_COLS
    mul cx                          ; row * 60  (DX destroyed, saved above)
    pop bx
    add bx, ax                      ; index = row*60 + column
    mov al, [level_work + bx]
    xor ah, ah
    jmp short .out
.sky:
    xor ax, ax
.out:
    pop dx
    pop cx
    pop bx
    pop bp
    ret 4

; ----------------------------------------------------------------------------
; SolidAt(px, py)  ->  AX = 1 when the tile there is solid (codes 1..10)
; Registers changed: AX only
; ----------------------------------------------------------------------------
SolidAt:
    push bp
    mov bp, sp
    push word [bp+6]
    push word [bp+4]
    call GetTile
    cmp ax, T_GROUND
    jb .no
    cmp ax, T_STAIR
    ja .no
    mov ax, 1
    jmp short .out
.no:
    xor ax, ax
.out:
    pop bp
    ret 4

; ----------------------------------------------------------------------------
; DrawTile(x, y, code)
; Purpose : draw one 16x16 tile. Opaque, fully visible tiles use a fast row
;           copy (REP MOVSW); partly visible or see-through tiles (pipes,
;           coins, flag pole) go through DrawSprite which clips and skips
;           colour 0.
; Registers changed: none
; ----------------------------------------------------------------------------
DrawTile:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push si
    push di
    push es
    mov bx, [bp+4]                  ; tile code
    mov al, [tile_block + bx]
    cmp al, 0FFh
    je .done                        ; sky has no art
    xor ah, ah
    mov cl, 8
    shl ax, cl                      ; block number * 256 bytes
    add ax, tile_ground             ; address of this tile's art
    mov si, ax
    cmp bx, T_STAIR
    je .opaque
    cmp bx, T_PIPE_TL
    jae .sprite                     ; pipes (6..9), coin, flag: see-through
.opaque:
    mov ax, [bp+8]                  ; x must be fully on screen for the fast path
    test ax, ax
    jl .sprite
    cmp ax, SCREEN_W - TILE_SIZE
    jg .sprite
    mov di, [bp+6]
    mov cl, 8
    shl di, cl
    mov bx, [bp+6]
    mov cl, 6
    shl bx, cl
    add di, bx
    add di, ax                      ; di = y*320 + x
    mov es, [fb_seg]
    cld
    mov bx, TILE_SIZE
.rows:
    mov cx, TILE_SIZE / 2
    rep movsw
    add di, SCREEN_W - TILE_SIZE
    dec bx
    jnz .rows
    jmp short .done
.sprite:
    push word [bp+8]
    push word [bp+6]
    push si
    xor ax, ax
    push ax
    call DrawSprite
.done:
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6

; ----------------------------------------------------------------------------
; DrawMap
; Purpose : draw the visible part of the working map: the 20 visible columns
;           plus one partial column, starting at column camera/16, shifted
;           left by camera mod 16 pixels. Rows 1..11 (row 0 belongs to HUD).
; Registers changed: none
; ----------------------------------------------------------------------------
DrawMap:
    push bp
    mov bp, sp
    sub sp, 8                       ; -2 column, -4 last column, -6 row, -8 tile
    push ax
    push bx
    push cx
    push dx
    mov ax, [camera]
    mov cl, 4
    shr ax, cl
    mov [bp-2], ax                  ; first column = camera / 16
    add ax, 20
    mov [bp-4], ax                  ; last column = first + 20 (21 columns)
.colloop:
    mov ax, [bp-2]
    cmp ax, LEVEL_COLS
    jae .done
    cmp ax, [bp-4]
    jg .done
    mov word [bp-6], 1              ; start at row 1
.rowloop:
    mov ax, [bp-6]
    mov cx, LEVEL_COLS
    push dx
    mul cx                          ; row * 60
    pop dx
    mov bx, ax
    add bx, [bp-2]                  ; + column = index into the map
    mov al, [level_work + bx]
    xor ah, ah
    test ax, ax
    jz .nexttile                    ; sky: nothing to draw
    mov [bp-8], ax                  ; remember the tile code
    mov ax, [bp-2]
    mov cl, 4
    shl ax, cl
    sub ax, [camera]                ; screen x = column*16 - camera
    push ax
    mov ax, [bp-6]
    mov cl, 4
    shl ax, cl                      ; screen y = row*16
    push ax
    push word [bp-8]                ; tile code
    call DrawTile
.nexttile:
    inc word [bp-6]
    cmp word [bp-6], LEVEL_ROWS
    jb .rowloop
    inc word [bp-2]
    jmp short .colloop
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret

; ----------------------------------------------------------------------------
; DrawGlyph(x, y, glyph_address, colour, scale)
; Purpose : draw one 8x8 bitmap character; every set bit becomes a
;           scale x scale square (so big titles reuse the same font).
; Registers changed: none
; ----------------------------------------------------------------------------
DrawGlyph:
    push bp
    mov bp, sp
    sub sp, 6                       ; -2 row, -4 bits, -6 column
    push ax
    push bx
    push dx
    mov word [bp-2], 0
.row:
    mov bx, [bp-2]
    add bx, [bp+8]                  ; glyph + row
    mov al, [bx]
    xor ah, ah
    mov [bp-4], ax                  ; the 8 bits of this row
    mov word [bp-6], 0
.col:
    test word [bp-4], 80h
    jz .next
    mov ax, [bp-6]
    mul word [bp+4]                 ; column * scale
    add ax, [bp+12]
    push ax                         ; x
    mov ax, [bp-2]
    mul word [bp+4]
    add ax, [bp+10]
    push ax                         ; y
    push word [bp+4]                ; w = scale
    push word [bp+4]                ; h = scale
    push word [bp+6]                ; colour
    call FillRect
.next:
    shl word [bp-4], 1
    inc word [bp-6]
    cmp word [bp-6], 8
    jb .col
    inc word [bp-2]
    cmp word [bp-2], 8
    jb .row
    pop dx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret 10

; ----------------------------------------------------------------------------
; DrawText(x, y, string_address, colour, scale)
; Purpose : draw a zero-terminated string with our copy of the BIOS font
;           (font_buf); characters 128/129 are the two heart icons.
; Registers changed: none
; ----------------------------------------------------------------------------
DrawText:
    push bp
    mov bp, sp
    sub sp, 2                       ; -2 current x
    push ax
    push bx
    push cx
    push si
    mov ax, [bp+12]
    mov [bp-2], ax
    mov si, [bp+8]
.next:
    lodsb
    or al, al
    jz .done
    xor ah, ah
    mov cl, 3
    shl ax, cl                      ; character * 8
    add ax, font_buf
    push word [bp-2]
    push word [bp+10]
    push ax
    push word [bp+6]
    push word [bp+4]
    call DrawGlyph
    mov ax, [bp+4]
    mov cl, 3
    shl ax, cl                      ; 8 * scale
    add [bp-2], ax
    jmp short .next
.done:
    pop si
    pop cx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret 10

; ----------------------------------------------------------------------------
; DrawNumber(x, y, value_low, value_high, digits, colour, scale)
; Purpose : print a 32-bit unsigned number with a fixed number of digits
;           (zero padded). Decimal conversion is repeated division by 10: the
;           remainders are pushed on the stack and popped in reverse order.
; Registers changed: none
; ----------------------------------------------------------------------------
DrawNumber:
    push bp
    mov bp, sp
    sub sp, 2                       ; -2 = current x
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov ax, [bp+16]
    mov [bp-2], ax                  ; current x
    mov ax, [bp+12]                 ; low word of the value
    mov bx, [bp+10]                 ; high word of the value
    mov cx, [bp+8]                  ; number of digits
    mov si, 10
.divide:
    push ax                         ; save the low word
    mov ax, bx
    xor dx, dx
    div si                          ; high word / 10
    mov bx, ax                      ; new high word
    pop ax                          ; DX:AX = remainder : low word
    div si                          ; (remainder:low) / 10, DX = next digit
    push dx                         ; push the remainder on the stack
    loop .divide
    mov di, [bp+8]                  ; DI counts digits still to draw
.show:
    pop ax                          ; pop: most significant digit first
    add ax, '0'
    shl ax, 1
    shl ax, 1
    shl ax, 1                       ; character * 8
    add ax, font_buf
    push word [bp-2]                ; x
    push word [bp+14]               ; y
    push ax                         ; glyph address
    push word [bp+6]                ; colour
    push word [bp+4]                ; scale
    call DrawGlyph
    mov ax, [bp+4]
    shl ax, 1
    shl ax, 1
    shl ax, 1                       ; 8 * scale
    add [bp-2], ax
    dec di
    jnz .show
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret 14


; ############################################################################
; ## sys.inc
; ############################################################################
; ============================================================================
; sys.inc  -  Interrupt handlers, start-up, clean exit, score and helpers
; (Modules 1, 7, 8, 13 and the exit part of 15)
; ============================================================================

; ----------------------------------------------------------------------------
; KeyISR  -  our own INT 09h handler (Module 7)
; Purpose : read the scan code from port 60h and keep a 128-byte key-state
;           table: keys[code] = 1 while held, 0 when released (bit 7 set =
;           release). The extra E0h byte of arrow keys is ignored. hits[code]
;           is set to 1 only on a fresh press (edge) and cleared by the game.
; Finishes with the end-of-interrupt signal (OUT 20h,20h) and IRET.
; Registers changed: none (all saved and restored)
; ----------------------------------------------------------------------------
KeyISR:
    push ax
    push bx
    push ds
    push cs
    pop ds                          ; DS = our segment
    in al, 60h                      ; scan code from the keyboard controller
    cmp al, 0E0h
    je .eoi                         ; extended-key prefix: ignore this byte
    cmp al, 0E1h
    je .eoi
    mov bl, al
    and bl, 7Fh                     ; strip the release bit
    xor bh, bh
    test al, 80h
    jnz .release
    cmp byte [keys + bx], 0
    jne .held                       ; auto-repeat: already down, no new hit
    mov byte [hits + bx], 1
.held:
    mov byte [keys + bx], 1
    jmp short .eoi
.release:
    mov byte [keys + bx], 0
.eoi:
    mov al, 20h
    out 20h, al                     ; tell the interrupt controller we are done
    pop ds
    pop bx
    pop ax
    iret

; ----------------------------------------------------------------------------
; TimerISR  -  our INT 08h handler (Module 8)
; Purpose : the PIT is programmed to 30 Hz. Each tick increments `ticks`.
;           The original BIOS handler must still run at its normal 18.2 Hz
;           (DOS clock), so a 16-bit accumulator adds 39773 per tick and the
;           old handler is CHAINED to whenever it overflows (the old handler
;           sends the EOI itself). Otherwise we send the EOI here.
; Registers changed: none
; ----------------------------------------------------------------------------
TimerISR:
    push ax
    push ds
    push cs
    pop ds
    inc word [ticks]
    mov ax, PIT_DIVISOR
    add [tick_acc], ax
    jc .chain                       ; overflow: time for the original handler
    mov al, 20h
    out 20h, al
    pop ds
    pop ax
    iret
.chain:
    pop ds
    pop ax
    jmp far [cs:old_int08]          ; original handler ends with its own IRET

; ----------------------------------------------------------------------------
; InstallHooks
; Purpose : save the old INT 09h / INT 08h vectors (INT 21h AH=35h), install
;           ours (AH=25h) and reprogram the timer chip to 30 Hz.
; Registers changed: none
; ----------------------------------------------------------------------------
InstallHooks:
    push ax
    push bx
    push dx
    push es
    mov ax, 3509h
    int 21h
    mov [old_int09], bx
    mov [old_int09 + 2], es
    mov ax, 3508h
    int 21h
    mov [old_int08], bx
    mov [old_int08 + 2], es
    mov dx, KeyISR
    mov ax, 2509h
    int 21h
    mov dx, TimerISR
    mov ax, 2508h
    int 21h
    cli
    mov al, 36h                     ; channel 0, mode 3, 16-bit divisor
    out 43h, al
    mov ax, PIT_DIVISOR
    out 40h, al
    mov al, ah
    out 40h, al
    sti
    mov byte [hooks_on], 1
    pop es
    pop dx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; RestoreHooks
; Purpose : give the timer chip its normal rate (divisor 0 = 65536) and put
;           the original INT 08h / INT 09h vectors back. Called on every exit
;           path; does nothing if the hooks were never installed.
; Registers changed: none
; ----------------------------------------------------------------------------
RestoreHooks:
    push ax
    push dx
    push ds
    cmp byte [hooks_on], 0
    je .skip
    cli
    mov al, 36h
    out 43h, al
    xor al, al
    out 40h, al
    out 40h, al                     ; divisor 0 = 18.2 Hz again
    mov dx, [old_int08]             ; read offset first, then switch DS
    mov ax, [old_int08 + 2]
    mov ds, ax                      ; DS:DX = original INT 08h handler
    mov ax, 2508h
    int 21h
    push cs
    pop ds                          ; back to our data before reading the next
    mov dx, [old_int09]
    mov ax, [old_int09 + 2]
    mov ds, ax                      ; DS:DX = original INT 09h handler
    mov ax, 2509h
    int 21h
    sti
.skip:
    pop ds
    pop dx
    pop ax
    mov byte [hooks_on], 0
    ret

; ----------------------------------------------------------------------------
; WaitTick
; Purpose : wait until the tick counter changes, so the game runs at the
;           same speed on every computer (no delay loop).
; Registers changed: none
; ----------------------------------------------------------------------------
WaitTick:
    push ax
    mov ax, [ticks]
.wait:
    sti
    hlt                             ; sleep until the next interrupt
    cmp ax, [ticks]
    je .wait
    pop ax
    ret

; ----------------------------------------------------------------------------
; ClearHits - forget all fresh-press flags (REP STOSB).
; Registers changed: none
; ----------------------------------------------------------------------------
ClearHits:
    push ax
    push cx
    push di
    push es
    push cs
    pop es
    cld
    mov di, hits
    mov cx, 128
    xor al, al
    rep stosb
    pop es
    pop di
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; InitFont
; Purpose : copy the 8x8 BIOS ROM font (INT 10h AX=1130h BH=3) into font_buf
;           and append our two heart glyphs as characters 128 and 129.
; Registers changed: none
; ----------------------------------------------------------------------------
InitFont:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, 1130h
    mov bh, 3                       ; ROM 8x8 font, characters 0..127
    int 10h                         ; returns the table at ES:BP
    push es
    pop ds                          ; DS = font segment
    mov si, bp
    push cs
    pop es
    mov di, font_buf
    mov cx, 512                     ; 1024 bytes = 512 words
    cld
    rep movsw
    push cs
    pop ds
    mov si, heart_full_glyph        ; 16 bytes: full heart, empty heart
    mov cx, 8
    rep movsw
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; AddScore(points)
; Purpose : 32-bit score += points (ADD / ADC), clamped to 999,999.
; Registers changed: none
; ----------------------------------------------------------------------------
AddScore:
    push bp
    mov bp, sp
    push ax
    mov ax, [bp+4]
    add [score_lo], ax
    adc word [score_hi], 0          ; carry into the high word
    cmp word [score_hi], MAX_SCORE_HI
    jb .ok
    ja .clamp
    cmp word [score_lo], MAX_SCORE_LO
    jbe .ok
.clamp:
    mov word [score_hi], MAX_SCORE_HI
    mov word [score_lo], MAX_SCORE_LO
.ok:
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; AddCoin - coins + 1; at 100 coins the counter returns to 0 and a life is
;           gained (lives never exceed 99).
; Registers changed: none
; ----------------------------------------------------------------------------
AddCoin:
    inc word [coins]
    cmp word [coins], 100
    jb .done
    mov word [coins], 0
    call AddLife
.done:
    ret

; ----------------------------------------------------------------------------
; AddLife - lives + 1, capped at 99.
; ----------------------------------------------------------------------------
AddLife:
    cmp word [lives], MAX_LIVES
    jae .done
    inc word [lives]
.done:
    ret

; ----------------------------------------------------------------------------
; KeyHit(scancode)  ->  AX = 1 if that key was freshly pressed since the last
;                       ClearHits.            Registers changed: AX only
; ----------------------------------------------------------------------------
KeyHit:
    push bp
    mov bp, sp
    push bx
    mov bx, [bp+4]
    xor ax, ax
    mov al, [hits + bx]
    pop bx
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; KeyDown(scancode)  ->  AX = 1 while that key is held.
;                        Registers changed: AX only
; ----------------------------------------------------------------------------
KeyDown:
    push bp
    mov bp, sp
    push bx
    mov bx, [bp+4]
    xor ax, ax
    mov al, [keys + bx]
    pop bx
    pop bp
    ret 2


; ############################################################################
; ## hero.inc
; ############################################################################
; ============================================================================
; hero.inc  -  Player movement, physics, tile collision, camera, hurt/death/win
; (Modules 6, 9, 10 and the death/win logic of 15)
;
; Position is kept as whole pixels (hero_x, hero_fy) plus a separate fraction
; byte (hero_xf, hero_fyf); speeds are 8.8 fixed point (high byte = whole
; pixels, low byte = fraction). hero_fy is the pixel row just BELOW his feet,
; so the sprite top is hero_fy - height and the feet stay fixed when the form
; changes between Small (16 high) and Super (32 high).
; ============================================================================

; ----------------------------------------------------------------------------
; AddFixed(position_address, fraction_address, velocity)
; Purpose : position(8.8) += velocity(8.8, signed). The fraction byte is added
;           first; its carry is added to the whole part together with the
;           sign-extended high byte of the velocity.
; Registers changed: none
; ----------------------------------------------------------------------------
AddFixed:
    push bp
    mov bp, sp
    push ax
    push bx
    push si
    mov bx, [bp+4]                  ; velocity
    mov si, [bp+6]                  ; address of fraction word
    mov al, [si]
    add al, bl                      ; fraction + low byte of velocity
    mov [si], al                    ; (MOV and CBW do not touch the carry)
    mov al, bh
    cbw                             ; AX = signed whole-pixel part
    adc ax, 0                       ; + carry from the fraction
    mov si, [bp+8]                  ; address of position word
    add [si], ax
    pop si
    pop bx
    pop ax
    pop bp
    ret 6

; ----------------------------------------------------------------------------
; HeroHeight  ->  AX = 16 for Small Mario, 32 for Super Mario
; Registers changed: AX only
; ----------------------------------------------------------------------------
HeroHeight:
    mov ax, [form]
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1                       ; form * 16
    ret

; ----------------------------------------------------------------------------
; SolidColumn(px)  ->  AX = 1 if any solid tile touches the vertical line at
;                      world x = px along Mario's body (top to feet).
; Samples every 15 pixels (less than a tile) so no tile is skipped.
; Registers changed: AX only
; ----------------------------------------------------------------------------
SolidColumn:
    push bp
    mov bp, sp
    push bx
    push dx
    call HeroHeight
    mov dx, [hero_fy]
    sub dx, ax                      ; DX = top of the sprite
    mov bx, [hero_fy]
    dec bx                          ; BX = lowest body pixel row
.loop:
    cmp bx, dx
    jle .last
    push word [bp+4]
    push bx
    call SolidAt
    test ax, ax
    jnz .out
    sub bx, 15
    jmp short .loop
.last:
    push word [bp+4]
    push dx
    call SolidAt                    ; finally the top row itself
.out:
    pop dx
    pop bx
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; FlagColumn(px)  ->  AX = 1 if a flag-pole tile touches the line x = px
;                     along Mario's body.        Registers changed: AX only
; ----------------------------------------------------------------------------
FlagColumn:
    push bp
    mov bp, sp
    push bx
    push dx
    call HeroHeight
    mov dx, [hero_fy]
    sub dx, ax
    mov bx, [hero_fy]
    dec bx
.loop:
    cmp bx, dx
    jle .last
    push word [bp+4]
    push bx
    call GetTile
    cmp ax, T_FLAG
    je .yes
    sub bx, 15
    jmp short .loop
.last:
    push word [bp+4]
    push dx
    call GetTile
    cmp ax, T_FLAG
    je .yes
    xor ax, ax
    jmp short .out
.yes:
    mov ax, 1
.out:
    pop dx
    pop bx
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; UpdateHero  (frame steps 2 and 3, Section 5.13)
; Purpose : horizontal speed from the keys (accelerate, brake, friction, walk
;           or run limit), jump (ground only, variable height), gravity, then
;           move ONE AXIS AT A TIME with tile collision: horizontal first, then
;           vertical. Also: left screen wall, level end, block triggers when
;           the head hits a tile, landing (stomp chain reset), pit and flag.
; Registers changed: none
; ----------------------------------------------------------------------------
UpdateHero:
    push ax
    push bx
    push cx
    push dx
    push si
    mov ax, [hero_fy]
    mov [hero_prev_fy], ax          ; feet position before this frame's move

    ; ---- horizontal speed ----------------------------------------------------
    mov bx, WALK_MAX
    cmp byte [keys + SC_LSHIFT], 0
    je .maxset
    mov bx, RUN_MAX                 ; Left Shift = run limit
.maxset:
    mov ax, [hero_vx]
    cmp byte [keys + SC_RIGHT], 0
    jne .goright
    cmp byte [keys + SC_LEFT], 0
    jne .goleft
    test ax, ax                     ; no key: friction pulls speed to zero
    jz .storevx
    js .fricneg
    sub ax, FRICTION
    jns .storevx
    xor ax, ax                      ; do not cross zero
    jmp short .storevx
.fricneg:
    add ax, FRICTION
    js .storevx
    xor ax, ax
    jmp short .storevx
.goright:
    mov word [hero_face], 0
    test ax, ax
    jns .raccel
    add ax, BRAKE                   ; moving left: opposite key brakes harder
    jmp short .rclamp
.raccel:
    add ax, ACCEL
.rclamp:
    cmp ax, bx
    jle .storevx
    mov ax, bx
    jmp short .storevx
.goleft:
    mov word [hero_face], 1
    test ax, ax
    jg .lbrake
    sub ax, ACCEL
    jmp short .lclamp
.lbrake:
    sub ax, BRAKE
.lclamp:
    neg bx
    cmp ax, bx
    jge .storevx
    mov ax, bx
.storevx:
    mov [hero_vx], ax

    ; ---- move horizontally, then test the tiles in front --------------------
    mov ax, hero_x
    push ax
    mov ax, hero_xf
    push ax
    push word [hero_vx]
    call AddFixed
    mov ax, [hero_vx]
    test ax, ax
    jnz $+5
    jmp .edges
    js .leftwall
    mov ax, [hero_x]                ; moving right: right edge of the hit-box
    add ax, HB_RIGHT
    push ax
    call SolidColumn
    test ax, ax
    jz .edges
    mov ax, [hero_x]
    add ax, HB_RIGHT
    mov cl, 4
    shr ax, cl
    shl ax, cl                      ; left edge of the wall tile
    sub ax, HB_RIGHT + 1            ; stand against it
    mov [hero_x], ax
    mov word [hero_xf], 0
    mov word [hero_vx], 0
    jmp short .edges
.leftwall:
    mov ax, [hero_x]                ; moving left: left edge of the hit-box
    add ax, HB_LEFT
    push ax
    call SolidColumn
    test ax, ax
    jz .edges
    mov ax, [hero_x]
    add ax, HB_LEFT
    mov cl, 4
    shr ax, cl
    inc ax
    shl ax, cl                      ; right edge of the wall tile
    sub ax, HB_LEFT
    mov [hero_x], ax
    mov word [hero_xf], 0
    mov word [hero_vx], 0
.edges:
    mov ax, [camera]                ; invisible wall at the left screen edge
    cmp [hero_x], ax
    jge .rightend
    mov [hero_x], ax
    mov word [hero_xf], 0
    mov word [hero_vx], 0
.rightend:
    cmp word [hero_x], MAX_HERO_X   ; cannot pass the end of the level
    jle .vert
    mov word [hero_x], MAX_HERO_X
    mov word [hero_xf], 0
    mov word [hero_vx], 0

    ; ---- jump, variable jump height, gravity --------------------------------
.vert:
    cmp byte [keys + SC_SPACE], 0
    je .nospace
    cmp word [on_ground], 0
    je .gravity                     ; no double jump
    cmp word [jump_lock], 0
    jne .gravity                    ; Space still held from the last jump
    mov word [hero_vy], JUMP_START
    mov word [jump_lock], 1
    mov word [on_ground], 0
    jmp short .gravity
.nospace:
    mov word [jump_lock], 0
    mov ax, [hero_vy]
    cmp ax, JUMP_CUT                ; released while rising fast: cut the jump
    jge .gravity
    mov word [hero_vy], JUMP_CUT
.gravity:
    mov ax, [hero_vy]
    add ax, GRAVITY
    cmp ax, MAX_FALL
    jle .vyok
    mov ax, MAX_FALL
.vyok:
    mov [hero_vy], ax
    mov ax, hero_fy
    push ax
    mov ax, hero_fyf
    push ax
    push word [hero_vy]
    call AddFixed
    mov word [on_ground], 0
    mov ax, [hero_vy]
    test ax, ax
    js .rising

    ; ---- falling or standing: tile under the feet ---------------------------
    mov bx, [hero_x]
    mov dx, [hero_fy]               ; pixel row just below the feet
    mov ax, bx
    add ax, HB_LEFT
    push ax
    push dx
    call SolidAt
    test ax, ax
    jnz .land
    mov ax, bx
    add ax, HB_RIGHT
    push ax
    push dx
    call SolidAt
    test ax, ax
    jnz $+5
    jmp .checks
.land:
    mov ax, [hero_fy]
    mov cl, 4
    shr ax, cl
    shl ax, cl                      ; top of the tile he lands on
    mov [hero_fy], ax
    mov word [hero_fyf], 0
    mov word [hero_vy], 0
    mov word [on_ground], 1
    mov word [stomp_chain], 0       ; landing ends a stomp chain
    jmp .checks

    ; ---- rising: head against a tile above ------------------------------------
.rising:
    call HeroHeight
    mov dx, [hero_fy]
    sub dx, ax                      ; DX = top of the sprite
    mov bx, [hero_x]
    mov ax, bx
    add ax, HB_LEFT
    push ax
    push dx
    call SolidAt
    mov cx, ax
    mov ax, bx
    add ax, HB_RIGHT
    push ax
    push dx
    call SolidAt
    or cx, ax
    jz .checks                      ; nothing above his head
    mov si, bx                      ; choose the tile: centre first, else a corner
    add si, 8
    push si
    push dx
    call SolidAt
    test ax, ax
    jnz .pick
    mov si, bx
    add si, HB_LEFT
    push si
    push dx
    call SolidAt
    test ax, ax
    jnz .pick
    mov si, bx
    add si, HB_RIGHT
.pick:
    mov cl, 4
    mov ax, si
    shr ax, cl
    push ax                         ; argument 1 for BumpBlock: column
    mov ax, dx
    shr ax, cl
    push ax                         ; argument 2: row of the tile that was hit
    inc ax
    shl ax, cl                      ; bottom edge of that tile
    mov bx, ax
    call HeroHeight
    add ax, bx                      ; feet = tile bottom + height
    mov [hero_fy], ax
    mov word [hero_fyf], 0
    mov word [hero_vy], 0           ; he starts falling
    call BumpBlock                  ; trigger the block (Section 5.9)

    ; ---- pit and flag pole ---------------------------------------------------------
.checks:
    call HeroHeight
    mov bx, [hero_fy]
    sub bx, ax                      ; top of the sprite
    cmp bx, MAP_PIXEL_H
    jl .flagchk
    xor ax, ax                      ; pit: no upward hop
    push ax
    call StartDeath
    jmp short .done
.flagchk:
    mov ax, [hero_x]
    add ax, HB_LEFT
    push ax
    call FlagColumn
    test ax, ax
    jnz .win
    mov ax, [hero_x]
    add ax, HB_RIGHT
    push ax
    call FlagColumn
    test ax, ax
    jz .done
.win:
    call StartWin
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; UpdateCamera  (frame step 8, Section 5.3)
; Purpose : follow Mario once he passes screen x = 160, clamp at the last
;           camera position, and never move the camera back to the left.
; Registers changed: none
; ----------------------------------------------------------------------------
UpdateCamera:
    push ax
    mov ax, [hero_x]
    sub ax, [camera]                ; screen_x = world_x - camera_x
    cmp ax, SCREEN_W / 2
    jle .done                       ; left of the middle: do not scroll
    mov ax, [hero_x]
    sub ax, SCREEN_W / 2            ; new camera so that screen_x = 160
    cmp ax, MAX_CAMERA
    jle .limited
    mov ax, MAX_CAMERA
.limited:
    cmp ax, [camera]
    jle .done                       ; max(camera, new): never scroll back
    mov [camera], ax
.done:
    pop ax
    ret

; ----------------------------------------------------------------------------
; HurtHero  (Section 5.7)
; Purpose : an enemy touched Mario. Ignored while invulnerable. Super Mario
;           becomes Small (2 s invulnerability); Small Mario dies.
; Registers changed: none
; ----------------------------------------------------------------------------
HurtHero:
    push ax
    cmp word [invuln], 0
    jne .done
    cmp word [form], 2
    jne .die
    mov word [form], 1              ; feet stay fixed, hearts change at once
    mov word [hp], 1
    mov word [invuln], INVULN_FRAMES
    jmp short .done
.die:
    mov ax, 1                       ; death with the upward hop
    push ax
    call StartDeath
.done:
    pop ax
    ret

; ----------------------------------------------------------------------------
; StartDeath(hop)
; Purpose : enter the DYING state: freeze everything and prepare the death
;           animation. hop = 1: jump up first; hop = 0 (pit): just keep falling.
; Registers changed: none
; ----------------------------------------------------------------------------
StartDeath:
    push bp
    mov bp, sp
    mov word [state], ST_DYING
    mov word [phase_timer], 0
    mov word [hero_vx], 0
    mov word [hero_vy], 0
    mov word [invuln], 0
    mov word [hero_hidden], 0
    mov word [on_ground], 0         ; the jump pose is drawn while he dies
    cmp word [bp+4], 0
    je .nohop
    mov word [hero_vy], DEATH_JUMP  ; about 48 pixels up
.nohop:
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; UpdateDying
; Purpose : one frame of the death animation: gravity only, no collisions.
; Outputs : AX = 1 when Mario has fallen off the bottom of the screen.
; Registers changed: AX only
; ----------------------------------------------------------------------------
UpdateDying:
    mov ax, [hero_vy]
    add ax, GRAVITY
    cmp ax, MAX_FALL
    jle .vyok
    mov ax, MAX_FALL
.vyok:
    mov [hero_vy], ax
    mov ax, hero_fy
    push ax
    mov ax, hero_fyf
    push ax
    push word [hero_vy]
    call AddFixed
    inc word [phase_timer]
    xor ax, ax
    cmp word [hero_fy], SCREEN_H + TILE_SIZE * 2
    jl .notyet
    mov ax, 1
.notyet:
    ret

; ----------------------------------------------------------------------------
; StartWin  (Section 5.11 steps 1-2)
; Purpose : the flag pole was touched: freeze the clock and controls (state
;           WIN), add the flag points for the height of Mario's bottom edge
;           (map row), and snap him to the pole.
; Registers changed: none
; ----------------------------------------------------------------------------
StartWin:
    push ax
    push cx
    mov word [state], ST_WIN
    mov word [win_phase], 0
    mov word [phase_timer], 0
    mov word [hero_vx], 0
    mov word [hero_vy], 0
    mov ax, [hero_fy]
    dec ax
    mov cl, 4
    shr ax, cl                      ; map row of his bottom edge
    cmp ax, 3
    jbe .p5000
    cmp ax, 4
    je .p2000
    cmp ax, 5
    je .p800
    cmp ax, 7
    jbe .p400
    mov ax, 100
    jmp short .award
.p5000:
    mov ax, 5000
    jmp short .award
.p2000:
    mov ax, 2000
    jmp short .award
.p800:
    mov ax, 800
    jmp short .award
.p400:
    mov ax, 400
.award:
    push ax
    call AddScore
    mov word [hero_x], FLAG_COL * TILE_SIZE - 4
    mov word [hero_xf], 0
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; UpdateWin  (Section 5.11 steps 2-4)
; Purpose : win sequence. Phase 0: slide down the pole to its base. Phase 1:
;           walk to the right for a moment. Phase 2: disappear (castle door).
;           Then the time bonus (time left x 50) is added and the state
;           changes to LEVEL COMPLETE.
; Registers changed: none
; ----------------------------------------------------------------------------
UpdateWin:
    push ax
    push cx
    push dx
    cmp word [win_phase], 0
    jne .phase1
    add word [hero_fy], 3           ; slide down the pole
    cmp word [hero_fy], 9 * TILE_SIZE
    jge $+5
    jmp .done
    mov word [hero_fy], 9 * TILE_SIZE
    mov word [win_phase], 1
    mov word [phase_timer], 0
    jmp .done
.phase1:
    cmp word [win_phase], 1
    jne .phase2
    mov word [hero_face], 0
    mov word [hero_vx], 1           ; "moving": the run pose is drawn
    mov word [on_ground], 1
    add word [hero_x], 2            ; walk towards the castle
    inc word [phase_timer]
    cmp word [phase_timer], 30
    jb .done
    mov word [win_phase], 2
    mov word [phase_timer], 0
    mov word [hero_hidden], 1
    jmp short .done
.phase2:
    inc word [phase_timer]
    cmp word [phase_timer], 20
    jb .done
    mov ax, [score_lo]              ; remember the score before the bonus
    mov [pre_score_lo], ax
    mov ax, [score_hi]
    mov [pre_score_hi], ax
    mov ax, [time_left]
    mov cx, 50
    mul cx                          ; bonus = time left x 50 (fits in 16 bits)
    mov [final_bonus], ax
    push ax
    call AddScore
    mov word [state], ST_COMPLETE
.done:
    pop dx
    pop cx
    pop ax
    ret


; ############################################################################
; ## ents.inc
; ############################################################################
; ============================================================================
; ents.inc  -  Enemies, shells, mushroom, coin pop-ups, blocks, coins
; (Modules 10, 11, 12)
; Entity records are 16 bytes (8 words): type, state, x, fraction, y, vy,
; direction, timer (offsets E_* in constants.inc). Slot offsets (0, 16, 32...)
; are passed to procedures; fields are reached with based-indexed addressing
; [entities + bx + E_X].
; ============================================================================

; ----------------------------------------------------------------------------
; ClearEntities - empty the whole entity table with REP STOSW.
; Registers changed: none
; ----------------------------------------------------------------------------
ClearEntities:
    push ax
    push cx
    push di
    push es
    push cs
    pop es
    cld
    mov di, entities
    mov cx, NUM_ENT * ENT_SIZE / 2
    xor ax, ax
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; SpawnEntity(type, state, x, y, direction)  ->  AX = slot offset, 0FFFFh if full
; Purpose : put a new record into the first free slot.
; Registers changed: AX only
; ----------------------------------------------------------------------------
SpawnEntity:
    push bp
    mov bp, sp
    push bx
    push cx
    xor bx, bx
    mov cx, NUM_ENT
.find:
    cmp word [entities + bx + E_TYPE], 0
    je .got
    add bx, ENT_SIZE
    loop .find
    mov ax, 0FFFFh                  ; table full
    jmp short .out
.got:
    mov ax, [bp+12]
    mov [entities + bx + E_TYPE], ax
    mov ax, [bp+10]
    mov [entities + bx + E_STATE], ax
    mov ax, [bp+8]
    mov [entities + bx + E_X], ax
    mov word [entities + bx + E_FRAC], 0
    mov ax, [bp+6]
    mov [entities + bx + E_Y], ax
    mov word [entities + bx + E_VY], 0
    mov ax, [bp+4]
    mov [entities + bx + E_DIR], ax
    mov word [entities + bx + E_TIMER], 0
    mov ax, bx
.out:
    pop cx
    pop bx
    pop bp
    ret 10

; ----------------------------------------------------------------------------
; InitEnemies
; Purpose : empty the table, then create every enemy of enemy_list (type,
;           column, row triples) standing still (ES_WAIT) and facing left.
; Registers changed: none
; ----------------------------------------------------------------------------
InitEnemies:
    push ax
    push cx
    push si
    call ClearEntities
    mov si, enemy_list
.next:
    xor ah, ah
    mov al, [si]
    test al, al
    jz .done
    push ax                         ; type
    mov ax, ES_WAIT
    push ax                         ; state
    xor ah, ah
    mov al, [si+1]
    mov cl, 4
    shl ax, cl
    push ax                         ; x = column * 16
    xor ah, ah
    mov al, [si+2]
    shl ax, cl
    push ax                         ; y = row * 16
    mov ax, -1
    push ax                         ; direction: left
    call SpawnEntity
    add si, 3
    jmp short .next
.done:
    pop si
    pop cx
    pop ax
    ret

; ----------------------------------------------------------------------------
; HeroOverlapsEnt(slot)  ->  AX = 1 if Mario's hit-box overlaps the entity
; Purpose : rectangle-overlap test (hit-box 12 wide, entity box 12 wide).
; Registers changed: AX only
; ----------------------------------------------------------------------------
HeroOverlapsEnt:
    push bp
    mov bp, sp
    push bx
    push cx
    push dx
    mov bx, [bp+4]
    call HeroHeight
    mov dx, [hero_fy]
    mov cx, dx
    sub cx, ax                      ; CX = Mario's top
    dec dx                          ; DX = Mario's bottom row
    mov ax, [entities + bx + E_Y]
    add ax, 15
    cmp cx, ax                      ; Mario's top below the entity's bottom?
    jg .no
    mov ax, [entities + bx + E_Y]
    cmp dx, ax                      ; Mario's bottom above the entity's top?
    jl .no
    mov ax, [entities + bx + E_X]
    add ax, 13
    mov cx, [hero_x]
    add cx, HB_LEFT
    cmp cx, ax                      ; Mario right of the entity?
    jg .no
    mov ax, [entities + bx + E_X]
    add ax, 2
    mov cx, [hero_x]
    add cx, HB_RIGHT
    cmp cx, ax                      ; Mario left of the entity?
    jl .no
    mov ax, 1
    jmp short .out
.no:
    xor ax, ax
.out:
    pop dx
    pop cx
    pop bx
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; EntOverlap(slotA, slotB)  ->  AX = 1 if two entities are closer than 12 pixels
;                               on both axes.          Registers changed: AX only
; ----------------------------------------------------------------------------
EntOverlap:
    push bp
    mov bp, sp
    push bx
    push si
    mov si, [bp+6]
    mov bx, [bp+4]
    mov ax, [entities + si + E_X]
    sub ax, [entities + bx + E_X]
    jns .xpos
    neg ax
.xpos:
    cmp ax, 12
    jge .no
    mov ax, [entities + si + E_Y]
    sub ax, [entities + bx + E_Y]
    jns .ypos
    neg ax
.ypos:
    cmp ax, 12
    jge .no
    mov ax, 1
    jmp short .out
.no:
    xor ax, ax
.out:
    pop si
    pop bx
    pop bp
    ret 4

; ----------------------------------------------------------------------------
; EntGravity(slot)
; Purpose : whole-pixel gravity for an entity: vy grows by 1 up to 4, the
;           entity falls, and lands on solid tiles under its feet.
; Registers changed: none
; ----------------------------------------------------------------------------
EntGravity:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    mov bx, [bp+4]
    mov ax, [entities + bx + E_VY]
    inc ax
    cmp ax, 4
    jle .vyok
    mov ax, 4
.vyok:
    mov [entities + bx + E_VY], ax
    add [entities + bx + E_Y], ax
    test ax, ax
    jle .done
    mov dx, [entities + bx + E_Y]
    add dx, TILE_SIZE               ; pixel row under the feet
    mov ax, [entities + bx + E_X]
    add ax, 3
    push ax
    push dx
    call SolidAt
    test ax, ax
    jnz .land
    mov ax, [entities + bx + E_X]
    add ax, 12
    push ax
    push dx
    call SolidAt
    test ax, ax
    jz .done
.land:
    mov ax, dx
    mov cl, 4
    shr ax, cl
    shl ax, cl                      ; top of the tile under it
    sub ax, TILE_SIZE
    mov [entities + bx + E_Y], ax
    mov word [entities + bx + E_VY], 0
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; EntMove(slot, speed, flags)
; Purpose : move an entity horizontally by +/-speed (8.8) along its direction.
;           It turns around when the tile in front is solid or at a level edge.
;           flags bit 0: also turn at platform edges (Koopa, not Goomba);
;           flags bit 1: also turn around at other walking enemies.
; Registers changed: none
; ----------------------------------------------------------------------------
EntMove:
    push bp
    mov bp, sp
    sub sp, 4                       ; -2 old x, -4 leading edge x
    push ax
    push bx
    push cx
    push dx
    push si
    mov bx, [bp+8]
    mov ax, [entities + bx + E_X]
    mov [bp-2], ax                  ; remember where we were
    mov dx, [bp+6]                  ; speed
    cmp word [entities + bx + E_DIR], 0
    jg .fwd
    neg dx                          ; moving left: negative velocity
.fwd:
    lea ax, [entities + bx + E_X]
    push ax
    lea ax, [entities + bx + E_FRAC]
    push ax
    push dx
    call AddFixed
    mov ax, [entities + bx + E_X]
    cmp word [entities + bx + E_DIR], 0
    jle .lead
    add ax, 15                      ; moving right: leading edge is the right side
.lead:
    mov [bp-4], ax
    cmp word [entities + bx + E_X], 0
    jge $+5                        ; level edges
    jmp .turn
    cmp word [entities + bx + E_X], MAX_HERO_X
    jle $+5
    jmp .turn
    push ax
    mov ax, [entities + bx + E_Y]
    add ax, 8
    mov dx, ax
    pop ax
    push ax
    push dx
    call SolidAt                    ; wall in front at mid height?
    test ax, ax
    jnz .turn
    test word [bp+4], 1
    jz .others
    cmp word [entities + bx + E_VY], 0
    jne .others                     ; in the air: no ledge check
    mov dx, [entities + bx + E_Y]
    add dx, TILE_SIZE
    push word [bp-4]
    push dx
    call SolidAt                    ; ground under the leading foot?
    test ax, ax
    jz .turn                        ; platform edge: turn around
.others:
    test word [bp+4], 2
    jz .done
    xor si, si
    mov cx, NUM_ENT
.scan:
    cmp si, bx
    je .nextj
    mov ax, [entities + si + E_TYPE]
    cmp ax, ET_GOOMBA
    je .check
    cmp ax, ET_KOOPA
    jne .nextj
.check:
    cmp word [entities + si + E_STATE], ES_WALK
    jne .nextj
    push si
    push bx
    call EntOverlap
    test ax, ax
    jnz .turn
.nextj:
    add si, ENT_SIZE
    loop .scan
    jmp short .done
.turn:
    mov ax, [bp-2]
    mov [entities + bx + E_X], ax   ; undo the step
    neg word [entities + bx + E_DIR]
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret 6

; ----------------------------------------------------------------------------
; ShellKills(slot)
; Purpose : a sliding shell removes every Goomba / Koopa it touches (+500 each).
; Registers changed: none
; ----------------------------------------------------------------------------
ShellKills:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push si
    mov bx, [bp+4]
    xor si, si
    mov cx, NUM_ENT
.scan:
    cmp si, bx
    je .next
    mov ax, [entities + si + E_TYPE]
    cmp ax, ET_GOOMBA
    je .cand
    cmp ax, ET_KOOPA
    jne .next
.cand:
    cmp word [entities + si + E_STATE], ES_FLAT
    je .next
    push si
    push bx
    call EntOverlap
    test ax, ax
    jz .next
    mov word [entities + si + E_TYPE], ET_NONE
    mov ax, 500
    push ax
    call AddScore
.next:
    add si, ENT_SIZE
    loop .scan
    pop si
    pop cx
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; UpdateOne(slot)  -  one entity, one frame (Sections 5.5 and 5.9)
; Purpose : remove it if far left of the camera or below the map; wake it up
;           when it comes within one tile of the screen; then run the rules of
;           its type: Goomba, Koopa, shell (still / sliding), mushroom, coin.
; Registers changed: none
; ----------------------------------------------------------------------------
UpdateOne:
    push bp
    mov bp, sp
    push ax
    push bx
    mov bx, [bp+4]
    mov ax, [entities + bx + E_X]
    add ax, 32
    cmp ax, [camera]
    jge $+5                      ; more than 32 px left of the screen
    jmp .remove
    cmp word [entities + bx + E_Y], SCREEN_H
    jl $+5                     ; fell below the map
    jmp .remove
    mov ax, [entities + bx + E_TYPE]
    cmp ax, ET_COIN
    jne $+5
    jmp .coin
    cmp word [entities + bx + E_STATE], ES_WAIT
    je .wait
    cmp ax, ET_GOOMBA
    je .goomba
    cmp ax, ET_KOOPA
    je .koopa
    cmp ax, ET_SHELL
    je .shell
    cmp ax, ET_MUSH
    jne $+5
    jmp .mush
    jmp .done
.wait:
    mov ax, [entities + bx + E_X]
    sub ax, [camera]
    cmp ax, SCREEN_W + TILE_SIZE    ; within one tile of the visible screen?
    jl $+5
    jmp .done
    mov word [entities + bx + E_STATE], ES_WALK
    jmp .done
.goomba:
    cmp word [entities + bx + E_STATE], ES_FLAT
    jne .gwalk
    dec word [entities + bx + E_TIMER]
    jle $+5
    jmp .done
    jmp .remove               ; flat Goomba disappears after about 1 s
.gwalk:
    push bx
    mov ax, GOOMBA_SPEED
    push ax
    mov ax, 2                       ; turn at other enemies, but walk off ledges
    push ax
    call EntMove
    push bx
    call EntGravity
    jmp .done
.koopa:
    push bx
    mov ax, KOOPA_SPEED
    push ax
    mov ax, 3                       ; turn at platform edges and other enemies
    push ax
    call EntMove
    push bx
    call EntGravity
    jmp short .done
.shell:
    cmp word [entities + bx + E_TIMER], 0
    jle .nograce
    dec word [entities + bx + E_TIMER]
.nograce:
    cmp word [entities + bx + E_STATE], ES_SLIDE
    jne .shellgrav
    push bx
    mov ax, SHELL_SPEED
    push ax
    xor ax, ax
    push ax                         ; bounces off walls, no ledge check
    call EntMove
    push bx
    call ShellKills
.shellgrav:
    push bx
    call EntGravity
    jmp short .done
.mush:
    push bx
    mov ax, MUSH_SPEED
    push ax
    xor ax, ax
    push ax
    call EntMove
    push bx
    call EntGravity
    jmp short .done
.coin:
    sub word [entities + bx + E_Y], 3   ; the coin floats up
    inc word [entities + bx + E_TIMER]
    cmp word [entities + bx + E_TIMER], COIN_POP_FRAMES
    jb .done
.remove:
    mov word [entities + bx + E_TYPE], ET_NONE
.done:
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; UpdateEntities  (frame step 4) - walk the whole table with UpdateOne.
; Registers changed: none
; ----------------------------------------------------------------------------
UpdateEntities:
    push ax
    push bx
    push cx
    xor bx, bx
    mov cx, NUM_ENT
.loop:
    cmp word [entities + bx + E_TYPE], ET_NONE
    je .next
    push bx
    call UpdateOne
.next:
    add bx, ENT_SIZE
    loop .loop
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; StompScore  - points for the next stomp of the chain (table chain_pts); the
;               11th and later stomps give a life. Chain counter + 1.
; Registers changed: none
; ----------------------------------------------------------------------------
StompScore:
    push ax
    push bx
    mov ax, [stomp_chain]
    cmp ax, 10
    jae .oneup
    shl ax, 1
    mov bx, ax
    push word [chain_pts + bx]      ; indexed word table
    call AddScore
    jmp short .count
.oneup:
    call AddLife
.count:
    cmp word [stomp_chain], 20
    jae .done
    inc word [stomp_chain]
.done:
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; StompTest(slot)  ->  AX = 1 if this contact is a stomp (Section 5.6):
;                      Mario moves down AND his feet were above the upper half
;                      of the enemy in the previous frame.
; Registers changed: AX only
; ----------------------------------------------------------------------------
StompTest:
    push bp
    mov bp, sp
    push bx
    push dx
    mov bx, [bp+4]
    xor ax, ax
    cmp word [hero_vy], 0
    jle .out
    mov dx, [entities + bx + E_Y]
    add dx, 8
    cmp word [hero_prev_fy], dx
    jg .out
    mov ax, 1
.out:
    pop dx
    pop bx
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; Bounce(slot) - put Mario's feet on top of the entity and bounce him up
;                (higher while the jump key is held).
; Registers changed: none
; ----------------------------------------------------------------------------
Bounce:
    push bp
    mov bp, sp
    push ax
    push bx
    mov bx, [bp+4]
    mov ax, [entities + bx + E_Y]
    mov [hero_fy], ax
    mov word [hero_fyf], 0
    mov word [hero_vy], STOMP_BOUNCE
    cmp byte [keys + SC_SPACE], 0
    je .done
    mov word [hero_vy], STOMP_BOUNCE_HI
.done:
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; StompOrHurt(slot) - Mario touches a walking Goomba or Koopa.
;   stomp -> Goomba goes flat for about 1 s, Koopa becomes a still shell;
;            chain points, bounce.   side/bottom -> Mario is hurt.
; Registers changed: none
; ----------------------------------------------------------------------------
StompOrHurt:
    push bp
    mov bp, sp
    push ax
    push bx
    mov bx, [bp+4]
    push bx
    call StompTest
    test ax, ax
    jz .hurt
    call StompScore
    push bx
    call Bounce
    cmp word [entities + bx + E_TYPE], ET_GOOMBA
    jne .koopa
    mov word [entities + bx + E_STATE], ES_FLAT
    mov word [entities + bx + E_TIMER], FLAT_FRAMES
    jmp short .done
.koopa:
    mov word [entities + bx + E_TYPE], ET_SHELL
    mov word [entities + bx + E_STATE], ES_STILL
    mov word [entities + bx + E_TIMER], KICK_GRACE
    jmp short .done
.hurt:
    call HurtHero                   ; ignored while invulnerable
.done:
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; ShellTouch(slot) - Mario touches a shell that is not in its grace period.
;   still shell  -> kick: +400, it slides away from Mario, Mario is not hurt
;   sliding shell-> stomp stops it (chain points, bounce); side contact hurts
; Registers changed: none
; ----------------------------------------------------------------------------
ShellTouch:
    push bp
    mov bp, sp
    push ax
    push bx
    mov bx, [bp+4]
    cmp word [entities + bx + E_STATE], ES_SLIDE
    je .sliding
    mov ax, 400                     ; kick a stationary shell
    push ax
    call AddScore
    mov word [entities + bx + E_DIR], -1
    mov ax, [hero_x]
    cmp ax, [entities + bx + E_X]
    jge .go                         ; Mario is on the right: shell goes left
    mov word [entities + bx + E_DIR], 1
.go:
    mov word [entities + bx + E_STATE], ES_SLIDE
    mov word [entities + bx + E_TIMER], KICK_GRACE
    jmp short .done
.sliding:
    push bx
    call StompTest
    test ax, ax
    jz .hurt
    call StompScore
    push bx
    call Bounce
    mov word [entities + bx + E_STATE], ES_STILL
    mov word [entities + bx + E_TIMER], KICK_GRACE
    jmp short .done
.hurt:
    call HurtHero
.done:
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; ResolveEntities  (frame step 5) - Mario against every entity, in the order
; of Section 5.6: enemies (stomp or hurt), shells (kick / stop / hurt),
; mushrooms (+1000, Small becomes Super).
; Registers changed: none
; ----------------------------------------------------------------------------
ResolveEntities:
    push ax
    push bx
    push cx
    xor bx, bx
    mov cx, NUM_ENT
.loop:
    cmp word [state], ST_PLAYING
    je $+5                       ; he just died or won: stop resolving
    jmp .exit
    mov ax, [entities + bx + E_TYPE]
    cmp ax, ET_GOOMBA
    je .enemy
    cmp ax, ET_KOOPA
    je .enemy
    cmp ax, ET_SHELL
    je .shell
    cmp ax, ET_MUSH
    je .mush
    jmp short .next
.enemy:
    cmp word [entities + bx + E_STATE], ES_WALK
    jne .next                       ; waiting or flat: harmless
    push bx
    call HeroOverlapsEnt
    test ax, ax
    jz .next
    push bx
    call StompOrHurt
    jmp short .next
.shell:
    cmp word [entities + bx + E_TIMER], 0
    jg .next                        ; grace period: ignores Mario
    push bx
    call HeroOverlapsEnt
    test ax, ax
    jz .next
    push bx
    call ShellTouch
    jmp short .next
.mush:
    push bx
    call HeroOverlapsEnt
    test ax, ax
    jz .next
    mov ax, 1000
    push ax
    call AddScore
    mov word [form], 2              ; Small -> Super (stays 2 if already Super)
    mov word [hp], 2
    mov word [entities + bx + E_TYPE], ET_NONE
.next:
    add bx, ENT_SIZE
    loop .loop
.exit:
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; SetTileAt(px, py, code) - write a tile code into the WORKING map.
; Registers changed: none
; ----------------------------------------------------------------------------
SetTileAt:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    mov ax, [bp+8]
    cmp ax, LEVEL_PIXELS
    jae .out
    mov bx, [bp+6]
    cmp bx, MAP_PIXEL_H
    jae .out
    mov cl, 4
    shr ax, cl
    shr bx, cl
    push ax
    mov ax, bx
    mov cx, LEVEL_COLS
    mul cx
    pop bx
    add bx, ax
    mov al, [bp+4]
    mov [level_work + bx], al
.out:
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6

; ----------------------------------------------------------------------------
; TryCoinPair(py) - collect a map coin at height py under either side of the
;                   hit-box (+200, coins +1, tile becomes sky).
; Registers changed: none
; ----------------------------------------------------------------------------
TryCoinPair:
    push bp
    mov bp, sp
    push ax
    push bx
    mov bx, HB_LEFT
.again:
    mov ax, [hero_x]
    add ax, bx
    push ax
    push word [bp+4]
    call GetTile
    cmp ax, T_COIN
    jne .next
    mov ax, [hero_x]
    add ax, bx
    push ax
    push word [bp+4]
    xor ax, ax
    push ax
    call SetTileAt                  ; the coin disappears from the working map
    mov ax, 200
    push ax
    call AddScore
    call AddCoin
.next:
    cmp bx, HB_RIGHT
    je .done
    mov bx, HB_RIGHT
    jmp short .again
.done:
    pop bx
    pop ax
    pop bp
    ret 2

; ----------------------------------------------------------------------------
; CollectCoins - test the tiles at Mario's feet, middle and head.
; Registers changed: none
; ----------------------------------------------------------------------------
CollectCoins:
    push ax
    push bx
    push cx
    push dx
    call HeroHeight
    mov dx, [hero_fy]
    mov cx, dx
    sub cx, ax                      ; top
    dec dx                          ; bottom row
    mov bx, dx
    add bx, cx
    shr bx, 1                       ; middle
    push dx
    call TryCoinPair
    push bx
    call TryCoinPair
    push cx
    call TryCoinPair
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; BumpBlock(column, row)  (Section 5.9)
; Purpose : Mario's head hit this tile from below.
;   brick      : Super Mario destroys it (+50); Small Mario: nothing
;   "?" coin   : becomes an empty block, +200, coins +1, a coin pops out
;   "?" mush.  : becomes an empty block, a mushroom appears on top
;   empty/other: nothing
; Registers changed: none
; ----------------------------------------------------------------------------
BumpBlock:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    mov ax, [bp+4]                  ; row
    cmp ax, LEVEL_ROWS
    jb $+5
    jmp .out
    cmp word [bp+6], LEVEL_COLS
    jb $+5
    jmp .out
    mov cx, LEVEL_COLS
    mul cx
    mov bx, ax
    add bx, [bp+6]                  ; index = row*60 + column
    mov al, [level_work + bx]
    cmp al, T_BRICK
    je .brick
    cmp al, T_QCOIN
    je .qcoin
    cmp al, T_QMUSH
    je .qmush
    jmp .out
.brick:
    cmp word [form], 2
    jne .out                        ; Small Mario: the brick stays
    mov byte [level_work + bx], T_SKY
    mov ax, 50
    push ax
    call AddScore
    jmp short .out
.qcoin:
    mov byte [level_work + bx], T_EMPTY
    mov ax, 200
    push ax
    call AddScore
    call AddCoin
    mov ax, ET_COIN
    push ax
    mov ax, ES_STILL
    push ax
    jmp short .spawn
.qmush:
    mov byte [level_work + bx], T_EMPTY
    mov ax, ET_MUSH
    push ax
    mov ax, ES_WALK
    push ax
.spawn:
    mov cl, 4
    mov ax, [bp+6]
    shl ax, cl
    push ax                         ; x = column * 16
    mov ax, [bp+4]
    dec ax
    shl ax, cl
    push ax                         ; y = one tile above the block
    mov ax, 1
    push ax                         ; moving right
    call SpawnEntity
.out:
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 4


; ############################################################################
; ## render.inc
; ############################################################################
; ============================================================================
; render.inc  -  Drawing the playing field: entities, hero, HUD
; (Modules 4, 6, 13)
; ============================================================================

; ----------------------------------------------------------------------------
; DrawEntities
; Purpose : draw every active entity. screen_x = world_x - camera; entities
;           are drawn only when -16 < screen_x < 320. Goombas alternate their
;           mirror every 8 frames (walking animation); Koopas face their
;           direction of travel.
; Registers changed: none
; ----------------------------------------------------------------------------
DrawEntities:
    push ax
    push bx
    push cx
    push dx
    push si
    xor bx, bx
    mov cx, NUM_ENT
.loop:
    mov ax, [entities + bx + E_TYPE]
    test ax, ax
    jnz $+5
    jmp .next
    xor dx, dx                      ; flags
    cmp ax, ET_GOOMBA
    je .goomba
    cmp ax, ET_KOOPA
    je .koopa
    cmp ax, ET_SHELL
    je .shell
    cmp ax, ET_MUSH
    je .mush
    mov ax, spr_coin                ; ET_COIN
    jmp short .draw
.goomba:
    mov ax, spr_goomba_flat
    cmp word [entities + bx + E_STATE], ES_FLAT
    je .draw
    mov ax, spr_goomba
    test word [frame_cnt], 8
    jz .draw
    mov dx, SF_MIRROR
    jmp short .draw
.koopa:
    mov ax, spr_koopa
    cmp word [entities + bx + E_DIR], 0
    jle .draw
    mov dx, SF_MIRROR               ; the art faces left; mirror when going right
    jmp short .draw
.shell:
    mov ax, spr_shell
    jmp short .draw
.mush:
    mov ax, spr_mushroom
.draw:
    mov si, ax
    mov ax, [entities + bx + E_X]
    sub ax, [camera]                ; screen x
    cmp ax, -15
    jl .next                        ; completely left of the screen
    cmp ax, SCREEN_W
    jge .next                       ; completely right of the screen
    push ax
    push word [entities + bx + E_Y]
    push si
    push dx
    call DrawSprite
.next:
    add bx, ENT_SIZE
    loop .loop
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; DrawHero
; Purpose : draw Mario: stand / run / jump pose, Small (16x16) or Super
;           (16x32), mirrored when facing left. While invulnerable he is drawn
;           only on alternate frames (blinking).
; Registers changed: none
; ----------------------------------------------------------------------------
DrawHero:
    push ax
    push bx
    push cx
    push dx
    push si
    cmp word [hero_hidden], 0
    je $+5
    jmp .done
    cmp word [invuln], 0
    je .visible
    test word [frame_cnt], 1
    jz $+5                       ; blink: skip every second frame
    jmp .done
.visible:
    mov bx, 2                       ; pose 2 = jump (in the air)
    cmp word [on_ground], 0
    je .posed
    xor bx, bx                      ; pose 0 = stand
    cmp word [hero_vx], 0
    je .posed
    test word [frame_cnt], 4        ; moving: alternate stand / run
    jz .posed
    mov bx, 1                       ; pose 1 = run
.posed:
    mov cl, 8
    mov ax, bx
    shl ax, cl                      ; pose * 256 bytes
    add ax, spr_small_stand
    xor dx, dx
    cmp word [form], 2
    jne .small
    mov cl, 9
    mov ax, bx
    shl ax, cl                      ; pose * 512 bytes (16 x 32 sprites)
    add ax, spr_super_stand
    mov dx, SF_TALL
.small:
    cmp word [hero_face], 0
    je .noflip
    or dx, SF_MIRROR
.noflip:
    mov si, ax
    mov ax, [hero_x]
    sub ax, [camera]
    push ax                         ; screen x
    call HeroHeight
    mov bx, [hero_fy]
    sub bx, ax
    push bx                         ; top y = feet - height
    push si
    push dx
    call DrawSprite
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; DrawHUD  (Section 5.14)
; Purpose : fixed strip at the top: SCORE (6 digits, 32-bit), COINS, WORLD,
;           TIME (3 digits), LIVES and HEALTH (two hearts).
; Registers changed: none
; ----------------------------------------------------------------------------
DrawHUD:
    push ax
    xor ax, ax
    push ax
    push ax
    mov ax, SCREEN_W
    push ax
    mov ax, TILE_SIZE
    push ax
    xor ax, ax
    push ax
    call FillRect                   ; black HUD background
    TEXT 4,   0, s_score,  C_YELLOW, 1
    TEXT 70,  0, s_coins,  C_YELLOW, 1
    TEXT 124, 0, s_world,  C_YELLOW, 1
    TEXT 180, 0, s_time,   C_YELLOW, 1
    TEXT 226, 0, s_lives,  C_YELLOW, 1
    TEXT 272, 0, s_health, C_YELLOW, 1
    NUMBER 4, 8, [score_lo], [score_hi], 6, C_WHITE, 1
    TEXT 70,  8, s_x,      C_WHITE, 1
    NUMBER 78, 8, [coins], 0, 2, C_WHITE, 1
    TEXT 124, 8, s_w11,    C_WHITE, 1
    NUMBER 180, 8, [time_left], 0, 3, C_WHITE, 1
    TEXT 226, 8, s_x,      C_WHITE, 1
    NUMBER 234, 8, [lives], 0, 2, C_WHITE, 1
    cmp word [form], 2
    je .super
    TEXT 272, 8, s_hearts_one, C_RED, 1     ; Small: 1 filled + 1 empty
    jmp short .done
.super:
    TEXT 272, 8, s_hearts_full, C_RED, 1    ; Super: 2 filled
.done:
    pop ax
    ret

; ----------------------------------------------------------------------------
; RenderGame  (frame step 9) - clear, then background, tiles, items, enemies,
; Mario and HUD into the frame buffer. (FlipFrame, step 10, is called by the
; state handlers.)
; Registers changed: none
; ----------------------------------------------------------------------------
RenderGame:
    call ClearFrame
    call DrawMap
    call DrawEntities
    call DrawHero
    call DrawHUD
    ret

; ----------------------------------------------------------------------------
; DrawBox(x, y, w, h, border_colour, fill_colour)
; Purpose : a filled rectangle with a 2-pixel border (menus, screens).
; Registers changed: none
; ----------------------------------------------------------------------------
DrawBox:
    push bp
    mov bp, sp
    push ax
    push word [bp+14]
    push word [bp+12]
    push word [bp+10]
    push word [bp+8]
    push word [bp+6]
    call FillRect                   ; border colour over the whole box
    mov ax, [bp+14]
    add ax, 2
    push ax
    mov ax, [bp+12]
    add ax, 2
    push ax
    mov ax, [bp+10]
    sub ax, 4
    push ax
    mov ax, [bp+8]
    sub ax, 4
    push ax
    push word [bp+4]
    call FillRect                   ; fill colour inside
    pop ax
    pop bp
    ret 12


; ############################################################################
; ## screens.inc
; ############################################################################
; ============================================================================
; screens.inc  -  State machine, screens, reset / new game, clean exit
; (Modules 14 and 15)
; The main loop calls one handler per state through a jump table indexed by
; the state number (state_table). Each handler does its updates, draws one
; frame into the frame buffer and flips it to the screen.
; ============================================================================

; ----------------------------------------------------------------------------
; ResetLevel  (Section 5.8 table, "after losing a life")
; Purpose : restore the working map from the original, put every enemy back,
;           Mario at the start as Small Mario, clock 300, camera 0.
;           Score, coins and lives are NOT touched here.
; Registers changed: none
; ----------------------------------------------------------------------------
ResetLevel:
    push ax
    call ResetMap
    call InitEnemies
    mov word [hero_x], START_X
    mov word [hero_xf], 0
    mov word [hero_fy], START_FEET_Y
    mov word [hero_fyf], 0
    mov word [hero_prev_fy], START_FEET_Y
    mov word [hero_vx], 0
    mov word [hero_vy], 0
    mov word [hero_face], 0
    mov word [on_ground], 1
    mov word [form], 1
    mov word [hp], 1
    mov word [invuln], 0
    mov word [stomp_chain], 0
    mov word [jump_lock], 1         ; a held Space must not jump at once
    mov word [hero_hidden], 0
    mov word [camera], 0
    mov word [time_left], LEVEL_TIME
    mov ax, [ticks]
    mov [clock_last], ax
    mov word [state], ST_PLAYING
    call ClearHits
    pop ax
    ret

; ----------------------------------------------------------------------------
; NewGame - score 0, coins 0, lives 3, then ResetLevel.
; Registers changed: none
; ----------------------------------------------------------------------------
NewGame:
    mov word [score_lo], 0
    mov word [score_hi], 0
    mov word [coins], 0
    mov word [lives], START_LIVES
    call ResetLevel
    ret

; ----------------------------------------------------------------------------
; UpdateClock  (frame step 6)
; Purpose : count the invulnerability timer down every frame and the level
;           clock once per real second (30 timer ticks). At 0 Mario dies.
; Registers changed: none
; ----------------------------------------------------------------------------
UpdateClock:
    push ax
    cmp word [invuln], 0
    je .clock
    dec word [invuln]
.clock:
    mov ax, [ticks]
    sub ax, [clock_last]
    cmp ax, FRAMES_PER_SEC
    jb .done
    add word [clock_last], FRAMES_PER_SEC
    dec word [time_left]
    jnz .done
    mov ax, 1                       ; clock reached 0: Mario dies (with the hop)
    push ax
    call StartDeath
.done:
    pop ax
    ret

; ----------------------------------------------------------------------------
; TestScreen  (Module 2 test, debug key F3 on the title screen)
; Purpose : show every game colour as a square so the palette can be checked.
; Registers changed: none
; ----------------------------------------------------------------------------
TestScreen:
    push ax
    push bx
    call ClearFrameBlack
    xor bx, bx
.sw:
    mov ax, bx
    mov cl, 4
    shl ax, cl
    add ax, bx
    add ax, bx
    add ax, bx
    add ax, bx                      ; x = colour * 20
    push ax
    mov ax, 70
    push ax
    mov ax, 20
    push ax
    mov ax, 60
    push ax
    push bx                         ; colour index
    call FillRect
    inc bx
    cmp bx, 16
    jb .sw
    TEXT 64, 30, s_debug, C_WHITE, 1
    call FlipFrame
    call ClearHits
.wait:
    call WaitTick
    cmp byte [hits + SC_ENTER], 0
    jne .out
    cmp byte [hits + SC_ESC], 0
    je .wait
.out:
    call ClearHits
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; StateTitle - TITLE screen: brick border, title, START GAME / EXIT menu
;              (Up/Down move the highlight, Enter selects, Esc exits).
; ----------------------------------------------------------------------------
StateTitle:
    push ax
    push bx
    push cx
    call ClearFrame
    xor bx, bx
.top:                               ; brick border: top and bottom rows
    mov ax, bx
    mov cl, 4
    shl ax, cl
    push ax
    xor ax, ax
    push ax
    mov ax, T_BRICK
    push ax
    call DrawTile
    mov ax, bx
    mov cl, 4
    shl ax, cl
    push ax
    mov ax, 176
    push ax
    mov ax, T_BRICK
    push ax
    call DrawTile
    inc bx
    cmp bx, 20
    jb .top
    mov bx, 1
.side:                              ; left and right columns
    mov ax, bx
    mov cl, 4
    shl ax, cl
    mov cx, ax
    xor ax, ax
    push ax
    push cx
    mov ax, T_BRICK
    push ax
    call DrawTile
    mov ax, 304
    push ax
    push cx
    mov ax, T_BRICK
    push ax
    call DrawTile
    inc bx
    cmp bx, 11
    jb .side
    mov bx, 1
.ground:                            ; grass strip at the bottom
    mov ax, bx
    mov cl, 4
    shl ax, cl
    push ax
    mov ax, 160
    push ax
    mov ax, T_GROUND
    push ax
    call DrawTile
    inc bx
    cmp bx, 19
    jb .ground
    mov ax, 32                      ; Mario and a Goomba stand on the grass
    push ax
    mov ax, 144
    push ax
    mov ax, spr_small_stand
    push ax
    xor ax, ax
    push ax
    call DrawSprite
    mov ax, 256
    push ax
    mov ax, 144
    push ax
    mov ax, spr_goomba
    push ax
    xor ax, ax
    push ax
    call DrawSprite
    TEXT 31, 39, s_title1, C_BLACK, 3       ; shadow
    TEXT 28, 36, s_title1, C_RED, 3
    TEXT 116, 84, s_title2, C_WHITE, 1
    mov ax, 104
    push ax
    mov ax, 104
    push ax
    mov ax, 112
    push ax
    mov ax, 44
    push ax
    mov ax, C_WHITE
    push ax
    xor ax, ax
    push ax
    call DrawBox
    mov ax, C_WHITE
    mov bx, C_WHITE
    cmp word [menu_sel], 0
    jne .colours
    mov ax, C_YELLOW                ; highlighted entry is yellow
    jmp short .drawmenu
.colours:
    mov bx, C_YELLOW
.drawmenu:
    push ax
    push bx
    mov cx, ax                      ; colour of START
    mov ax, 130
    push ax
    mov ax, 114
    push ax
    mov ax, s_start
    push ax
    push cx
    mov ax, 1
    push ax
    call DrawText
    pop bx
    pop ax
    mov ax, 130
    push ax
    mov ax, 130
    push ax
    mov ax, s_exit
    push ax
    push bx
    mov ax, 1
    push ax
    call DrawText
    mov ax, [menu_sel]
    mov cl, 4
    shl ax, cl
    add ax, 114
    mov bx, ax
    mov ax, 114
    push ax
    push bx
    mov ax, s_arrow
    push ax
    mov ax, C_YELLOW
    push ax
    mov ax, 1
    push ax
    call DrawText
    TEXT 31, 167, s_group, C_BLACK, 1
    TEXT 30, 166, s_group, C_WHITE, 1
    call FlipFrame
    ; ---- input ----
    cmp byte [hits + SC_UP], 0
    je .down
    mov word [menu_sel], 0
.down:
    cmp byte [hits + SC_DOWN], 0
    je .enter
    mov word [menu_sel], 1
.enter:
    cmp byte [hits + SC_F3], 0
    je .f3done
    call TestScreen
.f3done:
    cmp byte [hits + SC_ESC], 0
    jne .quit
    cmp byte [hits + SC_ENTER], 0
    je .end
    cmp word [menu_sel], 0
    jne .quit
    call NewGame                    ; START GAME
    jmp short .end
.quit:
    mov word [state], ST_EXIT
.end:
    call ClearHits
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; StatePlaying - one frame in the order of Section 5.13 (step 1, the timer
;                tick, was done by the main loop):
;   2 keys, 3 Mario, 4 enemies, 5 collisions, 6 clock, 7 death/flag checks,
;   8 camera, 9 draw into the frame buffer, 10 copy to the screen.
; ----------------------------------------------------------------------------
StatePlaying:
    cmp byte [hits + SC_P], 0
    je .esc
    mov word [state], ST_PAUSED
    jmp .render
.esc:
    cmp byte [hits + SC_ESC], 0
    je .debug
    mov word [menu_sel], 0
    mov word [state], ST_TITLE
    jmp .finish
.debug:
    cmp byte [hits + SC_F1], 0
    je .f2
    mov word [time_left], 5         ; debug key F1: 5 seconds left
.f2:
    cmp byte [hits + SC_F2], 0
    je .update
    mov word [coins], 99            ; debug key F2: 99 coins
.update:
    call UpdateHero                 ; steps 2-3 (also pit and flag, step 7)
    cmp word [state], ST_PLAYING
    jne .render
    call UpdateEntities             ; step 4
    call ResolveEntities            ; step 5
    cmp word [state], ST_PLAYING
    jne .render
    call CollectCoins
    call UpdateClock                ; step 6 (clock 0 kills, step 7)
    cmp word [state], ST_PLAYING
    jne .render
    call UpdateCamera               ; step 8
.render:
    call RenderGame                 ; step 9
    call FlipFrame                  ; step 10
.finish:
    call ClearHits
    ret

; ----------------------------------------------------------------------------
; StatePaused - the picture stays visible with a PAUSED box; nothing updates.
;               P resumes, Esc returns to the title.
; ----------------------------------------------------------------------------
StatePaused:
    push ax
    cmp byte [hits + SC_P], 0
    je .esc
    mov ax, [ticks]
    mov [clock_last], ax            ; the clock did not run while paused
    mov word [state], ST_PLAYING
    jmp .end
.esc:
    cmp byte [hits + SC_ESC], 0
    je .draw
    mov word [menu_sel], 0
    mov word [state], ST_TITLE
    jmp short .end
.draw:
    call RenderGame
    mov ax, 64
    push ax
    mov ax, 76
    push ax
    mov ax, 192
    push ax
    mov ax, 56
    push ax
    mov ax, C_WHITE
    push ax
    xor ax, ax
    push ax
    call DrawBox
    TEXT 72, 84, s_paused, C_YELLOW, 2
    TEXT 92, 112, s_presspause, C_WHITE, 1
    call FlipFrame
.end:
    call ClearHits
    pop ax
    ret

; ----------------------------------------------------------------------------
; StateDying - death animation (Section 5.8): Mario hops up and falls off the
;              bottom with gravity only. Then lives - 1: Life-lost screen, or
;              Game Over when no life is left.
; ----------------------------------------------------------------------------
StateDying:
    call UpdateDying
    test ax, ax
    jz .render
    dec word [lives]
    jle .gameover
    mov word [phase_timer], FRAMES_PER_SEC * 2
    mov word [state], ST_LIFELOST
    jmp short .render
.gameover:
    mov word [lives], 0
    mov word [state], ST_GAMEOVER
.render:
    call RenderGame
    call FlipFrame
    call ClearHits
    ret

; ----------------------------------------------------------------------------
; StateLifeLost - black screen with world name, Mario icon and lives left for
;                 about 2 seconds, then the level restarts.
; ----------------------------------------------------------------------------
StateLifeLost:
    call ClearFrameBlack
    TEXT 52, 40, s_worldbig, C_WHITE, 3
    mov ax, 88
    push ax
    mov ax, 96
    push ax
    mov ax, spr_small_stand
    push ax
    xor ax, ax
    push ax
    call DrawSprite
    TEXT 140, 100, s_x, C_WHITE, 2
    NUMBER 170, 100, [lives], 0, 2, C_WHITE, 2
    TEXT 80, 150, s_livesleft, C_YELLOW, 2
    call FlipFrame
    dec word [phase_timer]
    jnz .end
    call ResetLevel                 ; map, enemies, clock, camera, Small Mario
.end:
    call ClearHits
    ret

; ----------------------------------------------------------------------------
; StateWin - win sequence frames (slide, walk, vanish), see UpdateWin.
; ----------------------------------------------------------------------------
StateWin:
    call UpdateWin
    call RenderGame
    call FlipFrame
    call ClearHits
    ret

; ----------------------------------------------------------------------------
; StateComplete - LEVEL COMPLETE screen: score, coins, time x 50, bonus and
;                 final score. Enter returns to the title (no extra life).
; ----------------------------------------------------------------------------
StateComplete:
    push ax
    call ClearFrameBlack
    mov ax, 24
    push ax
    mov ax, 12
    push ax
    mov ax, 272
    push ax
    mov ax, 176
    push ax
    mov ax, C_YELLOW
    push ax
    xor ax, ax
    push ax
    call DrawBox
    TEXT 40, 26, s_complete, C_YELLOW, 2
    TEXT 64, 68, s_lscore, C_WHITE, 1
    NUMBER 192, 68, [pre_score_lo], [pre_score_hi], 6, C_WHITE, 1
    TEXT 64, 84, s_lcoins, C_WHITE, 1
    TEXT 192, 84, s_x, C_WHITE, 1
    NUMBER 200, 84, [coins], 0, 2, C_WHITE, 1
    TEXT 64, 100, s_ltime, C_WHITE, 1
    NUMBER 192, 100, [time_left], 0, 3, C_WHITE, 1
    TEXT 224, 100, s_x50, C_WHITE, 1
    TEXT 64, 116, s_lbonus, C_WHITE, 1
    TEXT 184, 116, s_plus, C_WHITE, 1
    NUMBER 192, 116, [final_bonus], 0, 5, C_WHITE, 1
    TEXT 64, 132, s_lfinal, C_YELLOW, 1
    NUMBER 192, 132, [score_lo], [score_hi], 6, C_YELLOW, 1
    TEXT 68, 160, s_enter, C_GRASS, 1
    call FlipFrame
    cmp byte [hits + SC_ENTER], 0
    je .end
    mov word [menu_sel], 0
    mov word [state], ST_TITLE
.end:
    call ClearHits
    pop ax
    ret

; ----------------------------------------------------------------------------
; StateGameOver - GAME OVER screen with the final score; Enter -> title.
; ----------------------------------------------------------------------------
StateGameOver:
    push ax
    call ClearFrameBlack
    mov ax, 16
    push ax
    mov ax, 24
    push ax
    mov ax, 288
    push ax
    mov ax, 152
    push ax
    mov ax, C_RED
    push ax
    xor ax, ax
    push ax
    call DrawBox
    TEXT 24, 56, s_gameover, C_RED, 2
    TEXT 88, 100, s_finalscore, C_WHITE, 1
    NUMBER 192, 100, [score_lo], [score_hi], 6, C_WHITE, 1
    TEXT 96, 124, s_coins, C_YELLOW, 1
    NUMBER 144, 124, [coins], 0, 2, C_YELLOW, 1
    TEXT 184, 124, s_time, C_YELLOW, 1
    NUMBER 224, 124, [time_left], 0, 3, C_YELLOW, 1
    TEXT 60, 152, s_entertitle, C_GRASS, 1
    call FlipFrame
    cmp byte [hits + SC_ENTER], 0
    je .end
    mov word [menu_sel], 0
    mov word [state], ST_TITLE
.end:
    call ClearHits
    pop ax
    ret

; ----------------------------------------------------------------------------
; Shutdown - the single exit path: restore the timer rate and BOTH interrupt
;            vectors, go back to text mode, return to DOS (INT 21h AH=4Ch).
; ----------------------------------------------------------------------------
Shutdown:
    call RestoreHooks
    call SetTextMode
    mov ax, 4C00h
    int 21h



; ============================================================================
;  MODULE INCLUSION: DATA & ASSETS (data.asm)
; ============================================================================
;  Divided into two ASM files linked by include:
;    - In C/C++ style preprocessors:  #include "data.asm"
;    - In NASM native assembly:      %include "data.asm"
;
;  Why data is included at the bottom:
;  In a 16-bit DOS .COM file (org 100h), execution starts at the very first
;  instruction ('start:'). Placing all data variables, level layout, and
;  sprite artwork in 'data.asm' at the bottom of the file ensures that data bytes
;  are never accidentally executed by the CPU as machine code instructions.
; ============================================================================
; #include "data.asm"

%include "data.asm"
%include "data.asm"
