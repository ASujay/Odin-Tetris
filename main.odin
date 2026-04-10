package main

import "core:math/rand"
import "core:log"
import "vendor:raylib"

HEIGHT      :: 800
WIDTH       :: 400
BLOCK_SIZE  :: 25
GRID_WIDTH  :: WIDTH / BLOCK_SIZE
GRID_HEIGHT :: HEIGHT / BLOCK_SIZE
FALL_DELAY  :: 0.5                                   // block will fall every 0.5s
SPAWN_POINT :: GRID_WIDTH / 2

@(init)
startup :: proc "contextless" () {
    raylib.InitWindow(WIDTH, HEIGHT, "Tetris game written in Odin.")
    raylib.SetTargetFPS(60)
}

GameCell :: struct {
    filled: bool,
    color: raylib.Color,
}

BlockCoord :: [2]i32

GamePiece :: struct {
    coords: [4]BlockCoord,
    color: raylib.Color,
    type: PieceType,
}

PieceType :: enum {
    I, J, L, O, S, T, Z,
}

PIECES :: [PieceType]GamePiece {
    .I = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT - 1,   0}, {SPAWN_POINT - 2,   0}, {SPAWN_POINT + 1, 0}},  color = raylib.Color{0, 255, 255, 255}, type = .I},
    .J = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT,       1}, {SPAWN_POINT,       2}, {SPAWN_POINT - 1, 2}},  color = raylib.BLUE                   , type = .J},
    .L = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT,       1}, {SPAWN_POINT,       2}, {SPAWN_POINT + 1, 2}},  color = raylib.ORANGE                 , type = .L},
    .O = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT,       1}, {SPAWN_POINT + 1,   0}, {SPAWN_POINT + 1, 1}},  color = raylib.YELLOW                 , type = .O},
    .S = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT + 1,   0}, {SPAWN_POINT,       1}, {SPAWN_POINT - 1, 1}},  color = raylib.GREEN                  , type = .S},
    .T = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT,       1}, {SPAWN_POINT - 1,   0}, {SPAWN_POINT + 1, 0}},  color = raylib.PURPLE                 , type = .T},
    .Z = {coords = [4]BlockCoord {{SPAWN_POINT, 0}, {SPAWN_POINT - 1,   0}, {SPAWN_POINT,       1}, {SPAWN_POINT + 1, 1}},  color = raylib.RED                    , type = .Z},
} 

GameState :: struct {
    grid_data: [GRID_WIDTH * GRID_HEIGHT]GameCell,
    should_spawn: bool,
    fall_timer: f32,
    active_piece: GamePiece,                // this will contain the current piece in play
}

Movement_Direction :: enum {
    DOWN,
    LEFT, 
    RIGHT,
}

clear_lines :: proc(state: ^GameState) {
    write_row := GRID_HEIGHT - 1

    for read_row := GRID_HEIGHT - 1; read_row >= 0; read_row -= 1 {
        full := true

        // Check if row is full
        for col := 0; col < GRID_WIDTH; col += 1 {
            if !state.grid_data[read_row * GRID_WIDTH + col].filled {
                full = false
                break
            }
        }

        if !full {
            // Copy row down
            for col := 0; col < GRID_WIDTH; col += 1 {
                state.grid_data[write_row * GRID_WIDTH + col] =
                    state.grid_data[read_row * GRID_WIDTH + col]
            }
            write_row -= 1
        }
    }

    // Clear remaining rows at top
    for row := write_row; row >= 0; row -= 1 {
        for col := 0; col < GRID_WIDTH; col += 1 {
            state.grid_data[row * GRID_WIDTH + col] = GameCell{}
        }
    }
}

transform_piece :: proc(piece: GamePiece) -> GamePiece {
    // the first element of the piece will always be the pivot
    new_piece: GamePiece
    new_piece.type = piece.type
    new_piece.color = piece.color
    new_piece.coords[0] = piece.coords[0]
    for &block, idx in new_piece.coords {
        if idx != 0 {
            temp_x := piece.coords[idx].x - piece.coords[0].x
            temp_y := piece.coords[idx].y - piece.coords[0].y
            // 90-degree clockwise rotation: (x, y) -> (-y, x)
            new_x := -temp_y
            new_y := temp_x
            block.x = new_x + piece.coords[0].x
            block.y = new_y + piece.coords[0].y
        }
    }
    return new_piece
}

rotate_piece :: proc(state: ^GameState) {
    new_piece := transform_piece(state.active_piece)
    // check if the new_piece is valid
    is_valid := true

    // check validity
    for block in new_piece.coords {
        // we need to do bounds check and check if the blocks are not overlapping anything
        if block.x < 0 || block.x >= GRID_WIDTH || block.y < 0 || block.y >= GRID_HEIGHT {
            is_valid = false
            break;
        }
        
        if state.grid_data[block.x + GRID_WIDTH * block.y].filled {
            is_valid = false
            break;
        }
    }
    if is_valid {
        state.active_piece = new_piece
    }
}

can_move :: proc(state: ^GameState, direction: Movement_Direction) -> bool {
    // here we will check if the a block should continue falling down or not
    for block, idx in state.active_piece.coords {
        // we check if there is another block of the active piece below the current one
        // if yes we dont change the should_move boolean
        // if there is some grid data beneath the current block we do not move
        next_x := block.x
        next_y := block.y
        switch(direction) {
            case .DOWN:
                next_y = next_y + 1
            case .LEFT:
                next_x = next_x - 1
            case .RIGHT:
                next_x = next_x + 1
        }
        // there we check if there is something in the grid data
        switch(direction) {
            case .DOWN: {
                if next_y >= GRID_HEIGHT || state.grid_data[next_y * GRID_WIDTH + next_x].filled {
                    return false
                }
            }
            case .LEFT: {
                if next_x < 0 || state.grid_data[next_y * GRID_WIDTH + next_x].filled {
                    return false
                }
            }
            case .RIGHT: {
                if next_x >= GRID_WIDTH || state.grid_data[next_y * GRID_WIDTH + next_x].filled {
                    return false
                }
            }
        }
    }
    return true
}



update :: proc(state: ^GameState) {
    if state.should_spawn {
        // first we should check if there is
        switch rand.int_max(1000) % 7 {
            case 0:
                state.active_piece = PIECES[.I]
            case 1:
                state.active_piece = PIECES[.J]
            case 2:
                state.active_piece = PIECES[.L]
            case 3:
                state.active_piece = PIECES[.O]
            case 4:
                state.active_piece = PIECES[.S]
            case 5:
                state.active_piece = PIECES[.T]
            case 6:
                state.active_piece = PIECES[.Z]
        }
        state.should_spawn = false
    }

    state.fall_timer += raylib.GetFrameTime()
    if state.fall_timer > FALL_DELAY {
        state.fall_timer = 0
        // this is the render logic
        if can_move(state, .DOWN) {
            // update the coordinates
            for &block in state.active_piece.coords {
                block[1] += 1
            }
        } else {
            // if no movement is possible then we write to the render grid
            for block in state.active_piece.coords {
                x := block[0]
                y := block[1]
                state.grid_data[GRID_WIDTH * y + x] = GameCell {
                    filled = true,
                    color = state.active_piece.color,
                }

                clear_lines(state)
                state.should_spawn = true
            }

        }
    }
}

render :: proc(state: ^GameState) {
    for i:i32 = 0; i < GRID_WIDTH; i += 1 {
        for j:i32 = 0; j < GRID_HEIGHT; j += 1 {
            //fmt.println(i, j)
            if state.grid_data[j * GRID_WIDTH + i].filled {
                raylib.DrawRectangle(i * BLOCK_SIZE, j * BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE, state.grid_data[j * GRID_WIDTH + i].color)
            }
        }
    }

    // render the piece
    for coord in state.active_piece.coords {
        raylib.DrawRectangle(coord[0] * BLOCK_SIZE, coord[1] * BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE, state.active_piece.color)
    }
}

run :: proc() {
    state: GameState
    state.should_spawn = true
    for !raylib.WindowShouldClose() {
        if raylib.IsKeyPressed(raylib.KeyboardKey.Q) {
            break
        }

        if raylib.IsKeyPressedRepeat(raylib.KeyboardKey.DOWN) {
            state.fall_timer += 0.5
        }

        if raylib.IsKeyPressed(raylib.KeyboardKey.UP) {
            rotate_piece(&state)
        }

        if raylib.IsKeyPressed(raylib.KeyboardKey.LEFT) {
            if can_move(&state, .LEFT) {
                for &block in state.active_piece.coords {
                    block.x -= 1
                }
            }
        }

        if raylib.IsKeyPressed(raylib.KeyboardKey.RIGHT) {
            if can_move(&state, .RIGHT) {
                for &block in state.active_piece.coords {
                    block.x += 1
                }
            }
        }

        update(&state)

         // render stuff here
        raylib.BeginDrawing()
        raylib.ClearBackground(raylib.BLACK)
        raylib.DrawFPS(0, 0)

        // Here will be out rendering code
        for x:i32 = 0; x <= WIDTH; x += BLOCK_SIZE {
            raylib.DrawLine(x, 0, x, HEIGHT, raylib.LIGHTGRAY)
        }

        for y:i32 = 0; y <= HEIGHT; y += BLOCK_SIZE {
            raylib.DrawLine(0, y, WIDTH, y, raylib.LIGHTGRAY)
        }

        render(&state)

        raylib.EndDrawing()
    }
   
}

main :: proc() {
    context.logger = log.create_console_logger()
    run()
}
