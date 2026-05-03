import json
import os
import shutil
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox

EMPTY = "."
ATTACKER = "A"
DEFENDER = "D"
KING = "K"
BOARD_SIZE = 11
CELL_SIZE = 54
PROLOG_FILE = Path(__file__).with_name("hnefatafl_prolog.pl")


# runs prolog and gets results back as json
class PrologBackend:
    def __init__(self, logic_file):
        self.logic_file = Path(logic_file)
        self.swipl = self.find_swipl()
        if not self.swipl:
            raise RuntimeError("SWI-Prolog not found. Install it or set SWIPL_PATH.")
        if not self.logic_file.exists():
            raise RuntimeError(f"Prolog file not found: {self.logic_file}")

    def find_swipl(self):

        options = [
            os.environ.get("SWIPL_PATH"),
            shutil.which("swipl"),
            r"C:\Program Files\swipl\bin\swipl.exe",
            r"C:\Program Files (x86)\swipl\bin\swipl.exe",
        ]
        for p in options:
            if p and Path(p).exists():
                return p
        return None

    def call(self, *args, timeout=60):
        cmd = [self.swipl, "-q", "-s", str(self.logic_file), "--"] + [str(a) for a in args]
        res = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
        if res.returncode != 0:
            raise RuntimeError(res.stderr.strip() or "Prolog error")
        out = res.stdout.strip()
        if not out:
            raise RuntimeError("Prolog gave no output")
        data = json.loads(out)
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Prolog error"))
        return data

    def get_initial(self):
        return self.call("initial")

    def get_targets(self, board, turn, row, col):
        return self.call("targets", board, turn, row, col)

    def do_move(self, board, turn, move):
        return self.call("apply", board, turn, move[0], move[1], move[2], move[3])

    def get_best(self, board, turn, depth):
        # hard mode take time
        return self.call("best", board, turn, depth, timeout=180)


class HnefataflApp:

    DIFFICULTIES = {"Easy": 1, "Medium": 3, "Hard": 5}

    def __init__(self, root):
        self.root = root
        self.root.title("Hnefatafl")
        self.root.configure(bg="#2a1200")

        self.board = EMPTY * (BOARD_SIZE * BOARD_SIZE)
        self.turn = "attacker"
        self.result = None
        self.human_side = tk.StringVar(value="defender")
        self.difficulty = tk.StringVar(value="Easy")
        self.selected = None
        self.valid_moves = []
        self.thinking = False

        self.build_ui()

        try:
            self.backend = PrologBackend(PROLOG_FILE)
        except Exception as e:
            self.status.config(text=str(e))
            messagebox.showerror("Error", str(e))
            self.backend = None

        self.new_game()

    def build_ui(self):
        # top bar with controls
        bar = tk.Frame(self.root, padx=10, pady=8, bg="#2a1200")
        bar.pack(fill=tk.X)

        tk.Label(bar, text="Play as", bg="#2a1200", fg="#c8a060").pack(side=tk.LEFT)
        side_menu = tk.OptionMenu(bar, self.human_side, "attacker", "defender",
                                  command=lambda _: self.new_game())
        side_menu.config(bg="#4e2a10", fg="#f0d080", activebackground="#6b3a1f",
                         activeforeground="#f0d080", highlightthickness=0)
        side_menu["menu"].config(bg="#4e2a10", fg="#f0d080")
        side_menu.pack(side=tk.LEFT, padx=(4, 14))

        tk.Label(bar, text="Difficulty", bg="#2a1200", fg="#c8a060").pack(side=tk.LEFT)
        diff_menu = tk.OptionMenu(bar, self.difficulty, "Easy", "Medium", "Hard")
        diff_menu.config(bg="#4e2a10", fg="#f0d080", activebackground="#6b3a1f",
                         activeforeground="#f0d080", highlightthickness=0)
        diff_menu["menu"].config(bg="#4e2a10", fg="#f0d080")
        diff_menu.pack(side=tk.LEFT, padx=(4, 14))

        tk.Button(bar, text="New Game", command=self.new_game,
                  bg="#4e2a10", fg="#f0d080").pack(side=tk.LEFT)

        self.status = tk.Label(self.root, text="", anchor="w", padx=10,
                               bg="#2a1200", fg="#c8a060")
        self.status.pack(fill=tk.X)

        size = CELL_SIZE * BOARD_SIZE
        self.canvas = tk.Canvas(self.root, width=size, height=size,
                                bg="#3b2008", highlightthickness=0)
        self.canvas.pack(padx=10, pady=10)
        self.canvas.bind("<Button-1>", self.on_click)

    def new_game(self):
        if not self.backend:
            return
        self.thinking = False
        try:
            data = self.backend.get_initial()
        except Exception as e:
            self.status.config(text=str(e))
            messagebox.showerror("Error", str(e))
            return

        self.board = data["board"]
        self.turn = data["turn"]
        self.result = data.get("result")
        self.selected = None
        self.valid_moves = []

        self.draw_board()
        self.update_status()

        if self.turn == self.computer_side():
            self.root.after(300, self.computer_turn)

    def on_click(self, event):
        if not self.backend or self.result or self.thinking:
            return
        if self.turn != self.human_side.get():
            return

        row = event.y // CELL_SIZE + 1
        col = event.x // CELL_SIZE + 1

        if not (1 <= row <= BOARD_SIZE and 1 <= col <= BOARD_SIZE):
            return

        # if we already selected a piece and clicked a valid target square
        if self.selected and [row, col] in self.valid_moves:
            try:
                move = [self.selected[0], self.selected[1], row, col]
                data = self.backend.do_move(self.board, self.turn, move)
            except Exception as e:
                self.status.config(text=str(e))
                messagebox.showerror("Error", str(e))
                return

            self.selected = None
            self.valid_moves = []
            self.board = data["board"]
            self.turn = data["turn"]
            self.result = data.get("result")
            self.after_move()
            return

        # find out if we clicked on a piece we can move
        idx = (row - 1) * BOARD_SIZE + (col - 1)
        piece = self.board[idx]

        if piece == ATTACKER:
            owner = "attacker"
        elif piece == DEFENDER or piece == KING:
            owner = "defender"
        else:
            owner = None

        if owner == self.turn:
            try:
                data = self.backend.get_targets(self.board, self.turn, row, col)
            except Exception as e:
                self.status.config(text=str(e))
                messagebox.showerror("Error", str(e))
                return
            self.selected = (row, col)
            self.valid_moves = data["targets"]
        else:
            self.selected = None
            self.valid_moves = []

        self.draw_board()

    def computer_turn(self):
        if not self.backend or self.result or self.thinking:
            return
        if self.turn != self.computer_side():
            return

        self.thinking = True
        self.status.config(text="Computer thinking...")
        depth = self.DIFFICULTIES[self.difficulty.get()]
        board = self.board
        turn = self.turn

        def run():
            try:
                data = self.backend.get_best(board, turn, depth)

                def finish(d=data):
                    self.thinking = False
                    move = d.get("move")
                    self.board = d["board"]
                    self.turn = d["turn"]
                    self.result = d.get("result")
                    if move:
                        fr, fc, tr, tc = move
                        self.status.config(text=f"Computer: ({fr},{fc}) -> ({tr},{tc})")
                    self.after_move()

                self.root.after(0, finish)

            except Exception as e:
                def show_err(ex=e):
                    self.thinking = False
                    self.status.config(text=str(ex))
                    messagebox.showerror("Error", str(ex))
                self.root.after(0, show_err)

        threading.Thread(target=run, daemon=True).start()

    def after_move(self):
        self.draw_board()
        self.update_status()
        if self.result:
            messagebox.showinfo("Game Over", f"{self.result.title()} wins!")
            return
        if self.turn == self.computer_side():
            self.root.after(250, self.computer_turn)

    def update_status(self):
        if self.result:
            self.status.config(text=f"Game over - {self.result} wins.")
        elif self.turn == self.human_side.get():
            self.status.config(text=f"Your turn ({self.human_side.get()})")
        else:
            self.status.config(text=f"Computer's turn ({self.computer_side()})")

    def computer_side(self):
        if self.human_side.get() == "attacker":
            return "defender"
        return "attacker"

    def draw_board(self):
        self.canvas.delete("all")
        for r in range(1, BOARD_SIZE + 1):
            for c in range(1, BOARD_SIZE + 1):
                self.draw_cell(r, c)
                idx = (r - 1) * BOARD_SIZE + (c - 1)
                p = self.board[idx]
                if p != EMPTY:
                    self.draw_piece(r, c, p)

    def draw_cell(self, row, col):
        x1 = (col - 1) * CELL_SIZE
        y1 = (row - 1) * CELL_SIZE
        x2 = x1 + CELL_SIZE
        y2 = y1 + CELL_SIZE

        if (row + col) % 2 == 0:
            color = "#6b3a1f"
        else:
            color = "#4e2a10"

        # corners and throne
        if (row, col) in {(1, 1), (1, 11), (11, 1), (11, 11)}:
            color = "#1a0a00"
        elif (row, col) == (6, 6):
            color = "#2e1505"

        if self.selected == (row, col):
            color = "#1a4a7a"
        elif [row, col] in self.valid_moves:
            color = "#1a5c2a"

        self.canvas.create_rectangle(x1, y1, x2, y2, fill=color, outline="#2a1200")
        self.canvas.create_text(x1 + 5, y1 + 5, text=f"{row},{col}",
                                anchor="nw", fill="#a0622a", font=("Arial", 7))

    def draw_piece(self, row, col, piece):
        m = 8
        x1 = (col - 1) * CELL_SIZE + m
        y1 = (row - 1) * CELL_SIZE + m
        x2 = col * CELL_SIZE - m
        y2 = row * CELL_SIZE - m

        if piece == ATTACKER:
            fill = "#1f2933"
            fg = "#ffffff"
            label = "A"
        elif piece == DEFENDER:
            fill = "#f8f5ed"
            fg = "#111111"
            label = "D"
        else:
            fill = "#d4af37"
            fg = "#111111"
            label = "K"

        self.canvas.create_oval(x1, y1, x2, y2, fill=fill, outline="#222222", width=2)
        self.canvas.create_text((x1 + x2) / 2, (y1 + y2) / 2,
                                text=label, fill=fg, font=("Arial", 17, "bold"))


if __name__ == "__main__":
    window = tk.Tk()
    HnefataflApp(window)
    window.mainloop()
