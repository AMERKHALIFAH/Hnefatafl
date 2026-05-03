# Hnefatafl
Hnefatafl (Viking Chess) AI game implemented using Python (Tkinter GUI) and Prolog logic, featuring Alpha-Beta pruning, heuristic evaluation, and full game rules.

This project is an implementation of the Hnefatafl (Viking Chess) game using a combination of Python and Prolog.

### Features
- Interactive GUI built with Tkinter
- Game logic implemented in Prolog
- Full implementation of Hnefatafl rules
- AI opponent using Alpha-Beta pruning
- Heuristic evaluation function for decision making
- Multiple difficulty levels (Easy, Medium, Hard)

### Architecture
- **Representation:** Game state represented as pieces on an 11x11 board
- **Controller:** Python handles user interaction and communication with Prolog
- **Moves:** Legal moves and captures generated in Prolog
- **Utility:** Heuristic function evaluates board states
- **AI:** Alpha-Beta pruning selects optimal moves

### How it works
The Python GUI sends requests to the Prolog engine to:
- Get valid moves
- Apply moves
- Compute the best move for the AI

The Prolog backend processes the logic and returns results in JSON format.

### Technologies Used
- Python (Tkinter)
- SWI-Prolog
