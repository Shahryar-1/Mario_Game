; ============================================================================
;  SUPER MARIO ENGINE - DATA & ASSETS MODULE (data.asm)
; ============================================================================
;  Description :
;    This second ASM file contains all persistent game variables, state flags,
;    lookup tables, strings, level maps, and ASCII-art sprite/tile graphics.
;
;  Two-File Structure & Include Linkage:
;    - In C/C++ style preprocessors:  #include "mario.asm"
;    - In NASM native assembly:      Included into mario.asm via %include "data.asm"
;
;  Memory Model Note:
;    In a 16-bit DOS .COM program (starting at org 100h in CS=DS=ES=SS), code
;    executes from the beginning. Placing variables and data after all
;    procedures ensures the CPU will never execute data bytes as code.
; ============================================================================
; #include "mario.asm"

; ############################################################################
; ## data.inc
; ############################################################################
; ============================================================================
; data.inc  -  All variables, tables and strings, grouped by purpose (Module 1)
; Everything lives after the code in the single .COM segment, except the frame
; buffer, which is a second segment (fb_seg).
; ============================================================================

; ---- Palette: 16 colours, 6-bit R,G,B each (see C_* in constants.inc) --------
palette_data:
    db  0,  0,  0                   ; 0  black / transparent
    db 23, 37, 63                   ; 1  sky
    db 56, 10,  5                   ; 2  red
    db  8, 16, 56                   ; 3  blue
    db 60, 46, 30                   ; 4  skin
    db 38, 22,  6                   ; 5  brown
    db 50, 18,  6                   ; 6  brick
    db  8, 48,  6                   ; 7  grass
    db  2, 28,  4                   ; 8  dark green
    db 63, 63, 63                   ; 9  white
    db 63, 56,  8                   ; 10 yellow
    db 56, 42, 22                   ; 11 tan
    db 63, 34,  6                   ; 12 orange
    db 22, 10,  2                   ; 13 dark brown
    db  6, 44, 12                   ; 14 pipe green
    db 40, 40, 40                   ; 15 gray

; ---- System ---------------------------------------------------------------------
fb_seg          dw 0                ; segment of the off-screen frame buffer
ticks           dw 0                ; incremented 30 times a second by TimerISR
tick_acc        dw 0                ; accumulator that paces the old BIOS handler
old_int08       dd 0                ; original timer vector (offset, segment)
old_int09       dd 0                ; original keyboard vector
hooks_on        db 0                ; 1 while our handlers are installed
keys            times 128 db 0      ; key-state table: 1 = held
hits            times 128 db 0      ; fresh-press flags, cleared by the game

; ---- Game flow ------------------------------------------------------------------
state           dw ST_TITLE
menu_sel        dw 0                ; 0 = START GAME, 1 = EXIT
frame_cnt       dw 0                ; counts frames (blinking, animation)
phase_timer     dw 0                ; timer used by dying / life lost / win states
win_phase       dw 0                ; 0 slide down, 1 walk, 2 vanish

; ---- Hero (all positions in whole pixels + separate 8.8 fraction) -------------
hero_x          dw 0                ; world x of the sprite's left edge
hero_xf         dw 0                ; x fraction (low byte used)
hero_fy         dw 0                ; y of the pixel row just BELOW his feet
hero_fyf        dw 0                ; feet fraction
hero_prev_fy    dw 0                ; feet y at the start of the frame
hero_vx         dw 0                ; horizontal speed, 8.8 signed
hero_vy         dw 0                ; vertical speed, 8.8 signed
hero_face       dw 0                ; 0 = right, 1 = left
on_ground       dw 0
form            dw 1                ; 1 = Small, 2 = Super
hp              dw 1                ; health 1 or 2
invuln          dw 0                ; blink / invulnerability frames left
stomp_chain     dw 0                ; stomps since the last landing
jump_lock       dw 0                ; 1 until Space is released (no auto re-jump)
hero_hidden     dw 0                ; 1 while he walks "into the castle"

; ---- Score, clock, camera ---------------------------------------------------------
score_lo        dw 0
score_hi        dw 0
coins           dw 0
lives           dw START_LIVES
time_left       dw LEVEL_TIME
clock_last      dw 0                ; tick value when the clock last counted
camera          dw 0                ; world x of the left edge of the screen
final_bonus     dw 0                ; time bonus shown on the Level Complete screen
pre_score_lo    dw 0                ; score before the bonus (for that screen)
pre_score_hi    dw 0

; ---- Scratch used by the update procedures -----------------------------------------
tmp_a           dw 0
tmp_b           dw 0

; ---- Stomp chain table: points for stomp 1..10, 11+ = extra life ---------------------
chain_pts       dw 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000

; ---- Maps: level_orig is never changed, level_work is the one the game edits ---------
level_orig      times LEVEL_BYTES db 0
level_work      times LEVEL_BYTES db 0

; ---- Entity table: NUM_ENT records of ENT_SIZE bytes (see E_* offsets) ---------------
entities        times NUM_ENT * ENT_SIZE db 0

; ---- Fonts and texts -------------------------------------------------------------------
font_buf        times 1040 db 0     ; 130 characters of 8 bytes (0-127 BIOS, 128-129 hearts)

s_title1        db "SUPER MARIO", 0
s_title2        db "E N G I N E", 0
s_start         db "START GAME", 0
s_exit          db "EXIT", 0
s_arrow         db ">", 0
s_group         db "Group #00 | Name 1, Name 2, Name 3", 0
s_score         db "SCORE", 0
s_coins         db "COINS", 0
s_world         db "WORLD", 0
s_w11           db "1-1", 0
s_time          db "TIME", 0
s_lives         db "LIVES", 0
s_health        db "HEALTH", 0
s_x             db "x", 0
s_paused        db "P A U S E D", 0
s_presspause    db "Press P to resume", 0
s_worldbig      db "WORLD 1-1", 0
s_livesleft     db "LIVES LEFT", 0
s_complete      db "LEVEL COMPLETE!", 0
s_lscore        db "SCORE", 0
s_lcoins        db "COINS", 0
s_ltime         db "TIME LEFT", 0
s_lbonus        db "TIME BONUS", 0
s_lfinal        db "FINAL SCORE", 0
s_x50           db "x 50", 0
s_plus          db "+", 0
s_enter         db "Press ENTER to continue", 0
s_gameover      db "G A M E   O V E R", 0
s_finalscore    db "Final Score:", 0
s_entertitle    db "Press ENTER for the title", 0
s_hearts_full   db 128, 128, 0      ; two filled hearts
s_hearts_one    db 128, 129, 0      ; one filled, one empty
s_debug         db "F1 time=5  F2 coins=99", 0


; ############################################################################
; ## level.inc
; ############################################################################
; ============================================================================
; level.inc - Level 1-1 as text (60 x 12). ConvertLevel turns it into tile codes.
; Legend: . sky  # ground  B brick  c ?-coin  m ?-mushroom  e empty
;         [ ] pipe top-left/right   ( ) pipe body-left/right
;         S stair block  o coin  F flag pole
; Row 0 is the HUD row; ground is rows 10-11; Mario stands on row 9.
; ============================================================================
level_text:
    db "............................................................"    ; row  0
    db "............................................................"    ; row  1
    db "........................................................F..."    ; row  2
    db "........................................................F..."    ; row  3
    db "........................................................F..."    ; row  4
    db "..........................c.............................F..."    ; row  5
    db "........m.....BBcBB............c............BBmBB...S...F..."    ; row  6
    db ".....................ooo..........[]...ooo.........SSoooF..."    ; row  7
    db "...........o................[]....()..............SSS...F..."    ; row  8
    db "............................()....().............SSSS...S..."    ; row  9
    db "#####################...###############...##################"    ; row 10
    db "#####################...###############...##################"    ; row 11

; ---- Legend: (character, tile code) pairs, 0 ends the table ---------------------
level_legend:
    db '.', T_SKY
    db '#', T_GROUND
    db 'B', T_BRICK
    db 'c', T_QCOIN
    db 'm', T_QMUSH
    db 'e', T_EMPTY
    db '[', T_PIPE_TL
    db ']', T_PIPE_TR
    db '(', T_PIPE_BL
    db ')', T_PIPE_BR
    db 'S', T_STAIR
    db 'o', T_COIN
    db 'F', T_FLAG
    db 0, 0

; ---- Enemy start list: (type, column, row) triples, type 0 ends the list ---------
; 4 Goombas and 2 Koopas, all standing on row 9 (ground rows 10-11).
enemy_list:
    db ET_GOOMBA, 12, 9
    db ET_GOOMBA, 19, 9
    db ET_GOOMBA, 26, 9
    db ET_KOOPA,  37, 9
    db ET_KOOPA,  43, 9
    db ET_GOOMBA, 46, 9
    db 0, 0, 0

FLAG_COL        equ 56              ; column of the flag pole


; ############################################################################
; ## art.inc
; ############################################################################
; ============================================================================
; art.inc  -  Original sprite and tile artwork (Module 4)
; Every image is 16 rows of 16 characters. At start-up ConvertArt turns the
; letters into VGA colour indices (see art_charmap). '.' = transparent (0).
;   R red   B blue  S skin  N brown  C brick  G grass  g dark green
;   W white Y yellow T tan  O orange D dark outline  P pipe green  A gray
; ============================================================================

art_start:

; ---- Small Mario, 16 x 16 ---------------------------------------------------
spr_small_stand:
    db "....RRRRR......."
    db "...RRRRRRRRR...."
    db "...DDDSSDS......"
    db "..DSDSSSDSSS...."
    db "..DSDDSSSDSSS..."
    db "..DDSSSSDDDD...."
    db "....SSSSSSS....."
    db "...RRBRRRR......"
    db "..RRRBRRBRRR...."
    db ".RRRRBBBBRRRR..."
    db ".SSRBYBBYBRSS..."
    db ".SSSBBBBBBSSS..."
    db ".SSBBBBBBBBSS..."
    db "...BBB..BBB....."
    db "..DDD....DDD...."
    db ".DDDD....DDDD..."
spr_small_run:
    db "....RRRRR......."
    db "...RRRRRRRRR...."
    db "...DDDSSDS......"
    db "..DSDSSSDSSS...."
    db "..DSDDSSSDSSS..."
    db "..DDSSSSDDDD...."
    db "....SSSSSSS....."
    db "...RRRBRRR......"
    db "..RRRRBBRRRR...."
    db ".SSRRBBBBRRSS..."
    db ".SSSBYBBYBSSS..."
    db "..SSBBBBBBSS...."
    db "...BBBBBBBB....."
    db "..DDDBB..BDDD..."
    db ".DDD......DDDD.."
    db "DDD..........DD."
spr_small_jump:
    db ".....RRRRR..SS.."
    db "....RRRRRRRRRSS."
    db "....DDDSSDS.SSS."
    db "...DSDSSSDSSS.S."
    db "...DSDDSSSDSSS.."
    db "...DDSSSSDDDD..."
    db ".....SSSSSSS...."
    db "..SSRRBRRRBB...."
    db ".SSSRRRBRRBBB..."
    db ".SSRRRRBBBBBB..."
    db "..RRRBYBBYBBB..."
    db "...BBBBBBBBBB..."
    db "..BBBBBBBBBBB..."
    db "..DDD....BBB...."
    db ".DDDD.....DDD..."
    db ".DDD.......DDD.."

; ---- Super Mario, 16 x 32 (head kept, torso and legs stretched) ------------
spr_super_stand:
    db "....RRRRR......."
    db "...RRRRRRRRR...."
    db "...DDDSSDS......"
    db "..DSDSSSDSSS...."
    db "..DSDDSSSDSSS..."
    db "..DDSSSSDDDD...."
    db "....SSSSSSS....."
    db "...RRBRRRR......"
    db "...RRBRRRR......"
    db "...RRBRRRR......"
    db "..RRRBRRBRRR...."
    db "..RRRBRRBRRR...."
    db "..RRRBRRBRRR...."
    db ".RRRRBBBBRRRR..."
    db ".RRRRBBBBRRRR..."
    db ".RRRRBBBBRRRR..."
    db ".SSRBYBBYBRSS..."
    db ".SSRBYBBYBRSS..."
    db ".SSRBYBBYBRSS..."
    db ".SSSBBBBBBSSS..."
    db ".SSSBBBBBBSSS..."
    db ".SSSBBBBBBSSS..."
    db ".SSBBBBBBBBSS..."
    db ".SSBBBBBBBBSS..."
    db ".SSBBBBBBBBSS..."
    db "...BBB..BBB....."
    db "...BBB..BBB....."
    db "..DDD....DDD...."
    db "..DDD....DDD...."
    db ".DDDD....DDDD..."
    db ".DDDD....DDDD..."
    db ".DDDD....DDDD..."
spr_super_run:
    db "....RRRRR......."
    db "...RRRRRRRRR...."
    db "...DDDSSDS......"
    db "..DSDSSSDSSS...."
    db "..DSDDSSSDSSS..."
    db "..DDSSSSDDDD...."
    db "....SSSSSSS....."
    db "...RRRBRRR......"
    db "...RRRBRRR......"
    db "...RRRBRRR......"
    db "..RRRRBBRRRR...."
    db "..RRRRBBRRRR...."
    db "..RRRRBBRRRR...."
    db ".SSRRBBBBRRSS..."
    db ".SSRRBBBBRRSS..."
    db ".SSRRBBBBRRSS..."
    db ".SSSBYBBYBSSS..."
    db ".SSSBYBBYBSSS..."
    db ".SSSBYBBYBSSS..."
    db "..SSBBBBBBSS...."
    db "..SSBBBBBBSS...."
    db "..SSBBBBBBSS...."
    db "...BBBBBBBB....."
    db "...BBBBBBBB....."
    db "...BBBBBBBB....."
    db "..DDDBB..BDDD..."
    db "..DDDBB..BDDD..."
    db ".DDD......DDDD.."
    db ".DDD......DDDD.."
    db ".DDD..........DD."
    db ".DDD..........DD."
    db ".DDD..........DD."
spr_super_jump:
    db ".....RRRRR..SS.."
    db "....RRRRRRRRRSS."
    db "....DDDSSDS.SSS."
    db "...DSDSSSDSSS.S."
    db "...DSDDSSSDSSS.."
    db "...DDSSSSDDDD..."
    db ".....SSSSSSS...."
    db "..SSRRBRRRBB...."
    db "..SSRRBRRRBB...."
    db "..SSRRBRRRBB...."
    db ".SSSRRRBRRBBB..."
    db ".SSSRRRBRRBBB..."
    db ".SSSRRRBRRBBB..."
    db ".SSRRRRBBBBBB..."
    db ".SSRRRRBBBBBB..."
    db ".SSRRRRBBBBBB..."
    db "..RRRBYBBYBBB..."
    db "..RRRBYBBYBBB..."
    db "..RRRBYBBYBBB..."
    db "...BBBBBBBBBB..."
    db "...BBBBBBBBBB..."
    db "...BBBBBBBBBB..."
    db "..BBBBBBBBBBB..."
    db "..BBBBBBBBBBB..."
    db "..BBBBBBBBBBB..."
    db "..DDD....BBB...."
    db "..DDD....BBB...."
    db ".DDDD.....DDD..."
    db ".DDDD.....DDD..."
    db ".DDD.......DDD.."
    db ".DDD.......DDD.."
    db ".DDD.......DDD.."

; ---- Enemies, items ------------------------------------------------------------
spr_goomba:
    db "................"
    db ".....NNNNNN....."
    db "...NNNNNNNNNN..."
    db "..NNNNNNNNNNNN.."
    db ".NNWWDNNNNDWWNN."
    db ".NNWWDNNNNDWWNN."
    db "NNNNNNNNNNNNNNNN"
    db "NNNNNNNNNNNNNNNN"
    db ".NNNNNNNNNNNNNN."
    db "....TTTTTTTT...."
    db "...TTTTTTTTTT..."
    db "...TTTTTTTTTT..."
    db "..DDDD....DDDD.."
    db ".DDDDDD..DDDDDD."
    db ".DDDDDD..DDDDDD."
    db "................"
spr_goomba_flat:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "...NNNNNNNNNN..."
    db "..NNNNNNNNNNNN.."
    db ".NNWDNNNNNNDWNN."
    db "NNNNNNNNNNNNNNNN"
    db ".NNNNNNNNNNNNNN."
    db "..TTTTTTTTTTTT.."
    db "..DDDD....DDDD.."
    db "................"
spr_koopa:
    db "....SSS........."
    db "...SSSSS........"
    db "...SDSSSS......."
    db "...SSSSS........"
    db "....YYY.GGGG...."
    db "....YYYGGGgGG..."
    db "...YYYGGGGGgGG.."
    db "...YYGgGGGGgGG.."
    db "...YYGGgGGgGGG.."
    db "....YGGGGGGGG..."
    db "....YGGgGGgGG..."
    db ".....GGGGGGG...."
    db ".....YYYYYYY...."
    db "....YYY...YYY..."
    db "....YYY...YYY..."
    db "...DDDD...DDDD.."
spr_shell:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "......gggg......"
    db "....gGGGGGGg...."
    db "...gGGgGGgGGg..."
    db "..gGGGGGGGGGGg.."
    db "..gGgGGGGGGgGg.."
    db "..gGGGGGGGGGGg.."
    db "..WWWWWWWWWWWW.."
    db "...WWWWWWWWWW..."
    db "....WWWWWWWW...."
    db "................"
    db "................"
spr_mushroom:
    db "................"
    db ".....RRRRRR....."
    db "...RRRWWWRRRR..."
    db "..RRWWWWWRRRRR.."
    db ".RRRWWWWRRWWRRR."
    db ".RRRRWWRRRWWRRR."
    db "RRRRRRRRRRRRRRRR"
    db "RRRWWRRRRRWWWRRR"
    db ".RRRRRRRRRRRRRR."
    db "....SSSSSSSS...."
    db "...SSDSSSSDSS..."
    db "...SSDSSSSDSS..."
    db "...SSSSSSSSSS..."
    db "....SSSSSSSS...."
    db ".....SSSSSS....."
    db "................"
spr_coin:
    db "................"
    db ".....DDDDDD....."
    db "....DYYYYYYD...."
    db "...DYYYOOYYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYYOOYYYD..."
    db "....DYYYYYYD...."
    db ".....DDDDDD....."
    db "................"
    db "................"
    db "................"

; ---- Tiles (block number = index used by tile_block table) -------------------
tile_ground:                        ; block 0
    db "GGGGGGGGGGGGGGGG"
    db "GGGGGGGGGGGGGGGG"
    db "gGGGGgGGGGGgGGGG"
    db "gggggggggggggggg"
    db "NNNNNNNNNNNNNNNN"
    db "NNDNNNNNNNNNNDNN"
    db "NNNNNNNNDNNNNNNN"
    db "NNNNNNNNNNNNNNNN"
    db "NNNNDNNNNNNNNNNN"
    db "NNNNNNNNNNDNNNNN"
    db "NNNNNNNNNNNNNNNN"
    db "NDNNNNNNNNNNNDNN"
    db "NNNNNNNDNNNNNNNN"
    db "NNNNNNNNNNNNNNNN"
    db "NNDNNNNNNNNDNNNN"
    db "NNNNNNNNNNNNNNNN"
tile_brick:                         ; block 1
    db "DDDDDDDDDDDDDDDD"
    db "CCCCCCCDCCCCCCCD"
    db "CCCCCCCDCCCCCCCD"
    db "CCCCCCCDCCCCCCCD"
    db "DDDDDDDDDDDDDDDD"
    db "CCCDCCCCCCCDCCCC"
    db "CCCDCCCCCCCDCCCC"
    db "CCCDCCCCCCCDCCCC"
    db "DDDDDDDDDDDDDDDD"
    db "CCCCCCCDCCCCCCCD"
    db "CCCCCCCDCCCCCCCD"
    db "CCCCCCCDCCCCCCCD"
    db "DDDDDDDDDDDDDDDD"
    db "CCCDCCCCCCCDCCCC"
    db "CCCDCCCCCCCDCCCC"
    db "CCCDCCCCCCCDCCCC"
tile_question:                      ; block 2 (codes 3 and 4)
    db "DDDDDDDDDDDDDDDD"
    db "DOOOOOOOOOOOOOOD"
    db "DOOOOYYYYYYOOOOD"
    db "DOOOYYOOOOYYOOOD"
    db "DOOOYYOOOOYYOOOD"
    db "DOOOOOOOOYYOOOOD"
    db "DOOOOOOOYYOOOOOD"
    db "DOOOOOOYYOOOOOOD"
    db "DOOOOOOYYOOOOOOD"
    db "DOOOOOOOOOOOOOOD"
    db "DOOOOOOYYOOOOOOD"
    db "DOOOOOOYYOOOOOOD"
    db "DOOOOOOOOOOOOOOD"
    db "DOOOOOOOOOOOOOOD"
    db "DOOOOOOOOOOOOOOD"
    db "DDDDDDDDDDDDDDDD"
tile_empty:                         ; block 3
    db "DDDDDDDDDDDDDDDD"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DNNNNNNNNNNNNNND"
    db "DDDDDDDDDDDDDDDD"
tile_pipe_tl:                       ; block 4
    db "DDDDDDDDDDDDDDDD"
    db "DPPPPPPPPPPPPPPP"
    db "DPPWWPPPPPPPPPPP"
    db "DPPWWPPPPPPPPPPP"
    db "DPPWWPPPPPPPPPPP"
    db "DPPWWPPPPPPPPPPP"
    db "DPPWWPPPPPPPPPPP"
    db "DPPWWPPPPPPPPPPP"
    db "DDDDDDDDDDDDDDDD"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
tile_pipe_tr:                       ; block 5
    db "DDDDDDDDDDDDDDDD"
    db "PPPPPPPPPPPPgggD"
    db "PPPPPPPPPPPPgggD"
    db "PPPPPPPPPPPPgggD"
    db "PPPPPPPPPPPPgggD"
    db "PPPPPPPPPPPPgggD"
    db "PPPPPPPPPPPPgggD"
    db "PPPPPPPPPPPPgggD"
    db "DDDDDDDDDDDDDDDD"
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
tile_pipe_bl:                       ; block 6
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
    db "..DPPWWPPPPPPPPP"
tile_pipe_br:                       ; block 7
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
    db "PPPPPPPPPPPggD.."
tile_stair:                         ; block 8
    db "DDDDDDDDDDDDDDDD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DTTTTTTTTTTTTTTD"
    db "DNNNNNNNNNNNNNND"
    db "DDDDDDDDDDDDDDDD"
tile_coin:                          ; block 9
    db "................"
    db ".....DDDDDD....."
    db "....DYYYYYYD...."
    db "...DYYYOOYYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYOYYOYYD..."
    db "...DYYYOOYYYD..."
    db "....DYYYYYYD...."
    db ".....DDDDDD....."
    db "................"
    db "................"
    db "................"
tile_flag:                          ; block 10 (pole)
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"
    db ".......gGg......"

art_end:

; ---- Letter -> colour table used by ConvertArt: pairs (char, colour), 0 ends -
art_charmap:
    db '.', C_BLACK
    db 'R', C_RED
    db 'B', C_BLUE
    db 'S', C_SKIN
    db 'N', C_BROWN
    db 'C', C_BRICK
    db 'G', C_GRASS
    db 'g', C_DGREEN
    db 'W', C_WHITE
    db 'Y', C_YELLOW
    db 'T', C_TAN
    db 'O', C_ORANGE
    db 'D', C_DBROWN
    db 'P', C_PIPE
    db 'A', C_GRAY
    db 0, 0

; ---- Tile code -> block number inside the tile art (0FFh = no art) ------------
tile_block:
    db 0FFh, 0, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10

; ---- 8 x 8 heart glyphs, appended to the BIOS font as characters 128 and 129 --
heart_full_glyph:   db 066h,0FFh,0FFh,0FFh,07Eh,03Ch,018h,000h
heart_empty_glyph:  db 066h,099h,081h,081h,042h,024h,018h,000h