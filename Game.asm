bits 16
org 100h
section .text
start:
    ; Ensure DS = CS
    push cs
    pop ds

    ; Calculate back-buffer segment (CS + 1000h = next 64KB boundary)
    mov ax, cs
    add ax, 1000h
    mov [buf_seg], ax

    ; Switch to VGA Mode 13h (320x200, 256 colors)
    mov ax, 0013h
    int 10h

    ; Install custom keyboard interrupt handler (INT 09h) for smooth multi-key controls
    call install_keyboard

reset_full_game:
    mov word [score], 0
    mov byte [coins_collected], 0
    mov byte [lives], 3
    mov byte [current_level], 1
    mov byte [game_state], 0        ; 0 = Playing, 1 = Game Over, 2 = Victory

    call load_level


; ============================================================================
; MAIN GAME LOOP (60 FPS synced to VGA Vertical Retrace)
; ============================================================================
main_loop:
    ; Check ESC key to quit at any time
    cmp byte [key_esc], 1
    je exit_game

    ; Check current game state
    cmp byte [game_state], 0
    jne .end_screen_state

    ; --- ACTIVE GAMEPLAY STATE ---
    call update_mario
    call update_enemies
    call check_items_and_goal
    call draw_world
    call draw_hud
    call flip_buffer
    call wait_vsync
    inc byte [anim_tick]
    jmp main_loop

.end_screen_state:
    ; --- GAME OVER OR VICTORY SCREEN ---
    call draw_end_screen
    call wait_vsync

    ; Press R or SPACE to restart the game
    cmp byte [key_r], 1
    je reset_full_game
    cmp byte [key_space], 1
    je reset_full_game
    jmp main_loop

exit_game:
    call speaker_off
    call restore_keyboard

    ; Return to DOS 80x25 Text Mode (03h)
    mov ax, 0003h
    int 10h

    ; Exit to DOS
    mov ax, 4C00h
    int 21h
