:- use_module(library(lists)).

% board is 11x11
board_size(11).

% the 4 corner squares
corner(1, 1).
corner(1, 11).
corner(11, 1).
corner(11, 11).

% center square where king starts
throne(6, 6).

special_square(R, C) :- corner(R, C).
special_square(R, C) :- throne(R, C).

% difficulty levels
difficulty(easy, 1).
difficulty(medium, 3).
difficulty(hard, 5).

% pieces and ownership
owner(a, attacker).
owner(d, defender).
owner(k, defender).

opponent(attacker, defender).
opponent(defender, attacker).

% 4 movement directions (up down left right)
direction(1, 0).
direction(-1, 0).
direction(0, 1).
direction(0, -1).

% starting positions for all pieces
initial_board([
    piece(a,1,4), piece(a,1,5), piece(a,1,6), piece(a,1,7), piece(a,1,8), piece(a,2,6),
    piece(a,4,1), piece(a,5,1), piece(a,6,1), piece(a,7,1), piece(a,8,1), piece(a,6,2),
    piece(a,4,11), piece(a,5,11), piece(a,6,11), piece(a,7,11), piece(a,8,11), piece(a,6,10),
    piece(a,11,4), piece(a,11,5), piece(a,11,6), piece(a,11,7), piece(a,11,8), piece(a,10,6),

    piece(d,4,6),
    piece(d,5,5), piece(d,5,6), piece(d,5,7),
    piece(d,6,4), piece(d,6,5), piece(k,6,6), piece(d,6,7), piece(d,6,8),
    piece(d,7,5), piece(d,7,6), piece(d,7,7),
    piece(d,8,6)
]).

piece_symbol(a, 'A').
piece_symbol(d, 'D').
piece_symbol(k, 'K').

symbol_piece('A', a).
symbol_piece('D', d).
symbol_piece('K', k).

print_board(State) :-
    State = state(Board, Turn),
    format('Turn: ~w~n', [Turn]),
    write('   1 2 3 4 5 6 7 8 9 10 11'), nl,
    forall(between(1, 11, R),
        (   format('~w ', [R]),
            forall(between(1, 11, C),
                (   square_symbol(Board, R, C, S),
                    format('~w ', [S])
                )),
            nl
        )).

% check if row/col is inside the board
inside(R, C) :-
    board_size(Size),
    between(1, Size, R),
    between(1, Size, C).

piece_at(Board, R, C, Piece) :-
    member(piece(Piece, R, C), Board).

% square is empty if its inside and no piece is there
empty_at(Board, R, C) :-
    inside(R, C),
    \+ piece_at(Board, R, C, _).

% --------------------------------------------------
% Movement
% --------------------------------------------------

legal_move(state(Board, Turn), move(FR, FC, TR, TC)) :-
    piece_at(Board, FR, FC, Piece),
    owner(Piece, Turn),
    direction(DR, DC),
    reachable_square(Board, Piece, FR, FC, DR, DC, TR, TC),
    (Piece = k -> true ; 
    \+ stopped_in_sandwich(Board, Turn, TR, TC)).

stopped_in_sandwich(Board, Turn, R, C) :-
    opponent(Turn, Enemy),
    direction(DR, DC),
    R1 is R + DR, C1 is C + DC,
    R2 is R - DR, C2 is C - DC,
    hostile_square(Board, Enemy, R1, C1),
    hostile_square(Board, Enemy, R2, C2).

% piece slides in a direction, can pass over throne/corners but cant land on them
reachable_square(Board, Piece, R, C, DR, DC, TR, TC) :-
    R1 is R + DR,
    C1 is C + DC,
    empty_at(Board, R1, C1),
    (   can_land(Piece, R1, C1),
        TR = R1,
        TC = C1
    ;   can_pass(Piece, R1, C1),
        reachable_square(Board, Piece, R1, C1, DR, DC, TR, TC)
    ).

can_pass(k, _, _).
can_pass(Piece, R, C) :-
    Piece \= k,
    \+ special_square(R, C).

% king can land anywhere, normal pieces cant land on throne or corners
can_land(k, R, C) :- inside(R, C).
can_land(Piece, R, C) :-
    Piece \= k,
    inside(R, C),
    \+ special_square(R, C).

% hostile squares for capture checking
hostile_square(Board, attacker, R, C) :-
    (   piece_at(Board, R, C, a)
    ;   special_square(R, C), \+ piece_at(Board, R, C, _)
    ).
hostile_square(Board, defender, R, C) :-
    (   piece_at(Board, R, C, d)
    ;   special_square(R, C), \+ piece_at(Board, R, C, _)
    ).

% --------------------------------------------------
% Making moves and captures
% --------------------------------------------------

make_move(state(Board, Turn), move(FR, FC, TR, TC), state(BoardAfter, NextTurn)) :-
    piece_at(Board, FR, FC, Piece),
    move_piece(Board, Piece, FR, FC, TR, TC, BoardMoved),
    remove_captures(BoardMoved, Piece, Turn, TR, TC, BoardAfter),
    opponent(Turn, NextTurn).

move_piece(Board, Piece, FR, FC, TR, TC, [piece(Piece, TR, TC)|Rest]) :-
    select(piece(Piece, FR, FC), Board, Rest).

% king cant capture other pieces
remove_captures(Board, k, _, _, _, Board) :- !.
remove_captures(Board, _, Side, R, C, BoardAfter) :-
    findall(pos(CR, CC), captured_piece(Board, Side, R, C, CR, CC), Caps),
    remove_positions(Board, Caps, BoardAfter).

% a piece is captured if sandwiched between the moved piece and a hostile square
captured_piece(Board, Side, R, C, CR, CC) :-
    direction(DR, DC),
    CR is R + DR,
    CC is C + DC,
    BR is R + (2 * DR),
    BC is C + (2 * DC),
    opponent(Side, Enemy),
    piece_at(Board, CR, CC, EnemyPiece),
    EnemyPiece \= k,
    owner(EnemyPiece, Enemy),
    hostile_square(Board, Side, BR, BC).

remove_positions([], _, []).
remove_positions([piece(Piece, R, C)|Rest], Caps, Result) :-
    (   member(pos(R, C), Caps)
    ->  remove_positions(Rest, Caps, Result)
    ;   Result = [piece(Piece, R, C)|Tail],
        remove_positions(Rest, Caps, Tail)
    ).

% --------------------------------------------------
% Move ordering heuristics for alpha-beta
% --------------------------------------------------

get_ordered_moves(State, Player, Depth, Moves) :-
    findall(Score-Move,
        (   legal_move(State, Move),
            move_score(State, Move, Player, Score)
        ),
        Pairs),
    keysort(Pairs, Sorted),
    reverse(Sorted, SortedDesc),
    pairs_values(SortedDesc, AllMoves),
    get_move_limit(Depth, Limit),
    take_first(Limit, AllMoves, Moves).

get_move_limit(Depth, 8)  :- Depth >= 4, !.
get_move_limit(Depth, 12) :- Depth >= 3, !.
get_move_limit(Depth, 20) :- Depth >= 1, !.
get_move_limit(_, 200).

take_first(_, [], []) :- !.
take_first(0, _, []) :- !.
take_first(N, [X|Xs], [X|Ys]) :-
    N1 is N - 1,
    take_first(N1, Xs, Ys).

% score a move before searching it, to help alpha-beta move ordering
move_score(state(Board, _), move(FR, FC, TR, TC), Player, Score) :-
    piece_at(Board, FR, FC, Piece),
    defender_score(Board, Piece, TR, TC, DS),
    (Player = defender -> Score = DS ; Score is -DS).

% king wants to get to corner
defender_score(_, k, R, C, Score) :-
    (   corner(R, C)
    ->  Score = 10000
    ;   min_corner_dist(R, C, D),
        Score is 1000 - (D * 100)
    ).
% attacker wants to get close to king, to help with captures
defender_score(Board, a, R, C, Score) :-
    piece_at(Board, KR, KC, k),
    D is abs(R - KR) + abs(C - KC),
    Score is -500 + (D * 20).
% defender close to king is good, help with defense
defender_score(Board, d, R, C, Score) :-
    piece_at(Board, KR, KC, k),
    D is abs(R - KR) + abs(C - KC),
    Score is 100 - (D * 10).

min_corner_dist(R, C, Dist) :-
    findall(D, (corner(CR, CC), D is abs(R-CR) + abs(C-CC)), Ds),
    min_list(Ds, Dist).

legal_targets(State, Row, Col, Targets) :-
    findall([TR, TC], legal_move(State, move(Row, Col, TR, TC)), Raw),
    sort(Raw, Targets).

% --------------------------------------------------
% Win conditions
% --------------------------------------------------

game_result(state(Board, _), defender) :-
    quick_result(state(Board, _), defender), !.
game_result(state(Board, _), attacker) :-
    quick_result(state(Board, _), attacker), !.
game_result(state(Board, Turn), Winner) :-
    \+ legal_move(state(Board, Turn), _),
    opponent(Turn, Winner), !.

% king escaped to corner = defender wins
quick_result(state(Board, _), defender) :-
    piece_at(Board, R, C, k),
    corner(R, C), !.
% king removed from board = attacker wins
quick_result(state(Board, _), attacker) :-
    \+ piece_at(Board, _, _, k), !.
% king surrounded = attacker wins
quick_result(state(Board, _), attacker) :-
    king_captured(Board), !.

% king is captured when all 4 sides are blocked
% works for open board (4 attackers), wall (3+wall), corner (2+wall+corner)
king_captured(Board) :-
    piece_at(Board, R, C, k),
    count_blocking_sides(Board, R, C, 4).

count_blocking_sides(Board, R, C, Count) :-
    findall(1,
        (   direction(DR, DC),
            AR is R + DR,
            AC is C + DC,
            is_blocking_side(Board, AR, AC)
        ),
        Sides),
    length(Sides, Count).

is_blocking_side(Board, R, C) :- piece_at(Board, R, C, a).
is_blocking_side(_, R, C)     :- \+ inside(R, C).
is_blocking_side(_, R, C)     :- corner(R, C).

% --------------------------------------------------
% Alpha-Beta Search
% --------------------------------------------------

best_move(State, Depth, BestMove, BestVal) :-
    State = state(_, Player),
    get_ordered_moves(State, Player, Depth, Moves),
    Moves \= [],
    Depth1 is Depth - 1,
    best_move_loop(Moves, State, Depth1, Player, -1000000, 1000000, none, -1000000, BestMove, BestVal).

% loop over root moves and track best with proper alpha updates
best_move_loop([], _, _, _, _, _, Best, BestVal, Best, BestVal).
best_move_loop([Move|Rest], State, Depth, Player, Alpha, Beta, _BestSoFar, BestValSoFar, BestMove, BestVal) :-
    make_move(State, Move, Child),
    alpha_beta(Child, Depth, Alpha, Beta, Player, Val),
    Val > BestValSoFar, !,
    NewAlpha is max(Alpha, Val),
    (   NewAlpha >= Beta
    ->  BestMove = Move, BestVal = Val
    ;   best_move_loop(Rest, State, Depth, Player, NewAlpha, Beta, Move, Val, BestMove, BestVal)
    ).
best_move_loop([_|Rest], State, Depth, Player, Alpha, Beta, BestSoFar, BestValSoFar, BestMove, BestVal) :-
    best_move_loop(Rest, State, Depth, Player, Alpha, Beta, BestSoFar, BestValSoFar, BestMove, BestVal).

alpha_beta(State, Depth, _, _, Player, Val) :-
    quick_result(State, Winner), !,
    terminal_value(Winner, Player, Depth, Val).
alpha_beta(State, Depth, _, _, Player, Val) :-
    Depth =< 0, !,
    utility(State, Player, Val).
alpha_beta(State, Depth, Alpha, Beta, Player, Val) :-
    State = state(_, Turn),
    get_ordered_moves(State, Turn, Depth, Moves),
    (   Moves = []
    ->  opponent(Turn, Winner),
        terminal_value(Winner, Player, Depth, Val)
    ;   Depth1 is Depth - 1,
        (   Turn = Player
        ->  maximize(Moves, State, Depth1, Alpha, Beta, Player, Val)
        ;   minimize(Moves, State, Depth1, Alpha, Beta, Player, Val)
        )
    ).

maximize([], _, _, Alpha, _, _, Alpha).
maximize([Move|Moves], State, Depth, Alpha, Beta, Player, Val) :-
    make_move(State, Move, Child),
    alpha_beta(Child, Depth, Alpha, Beta, Player, ChildVal),
    NewAlpha is max(Alpha, ChildVal),
    (   NewAlpha >= Beta
    ->  Val = NewAlpha
    ;   maximize(Moves, State, Depth, NewAlpha, Beta, Player, Val)
    ).

minimize([], _, _, _, Beta, _, Beta).
minimize([Move|Moves], State, Depth, Alpha, Beta, Player, Val) :-
    make_move(State, Move, Child),
    alpha_beta(Child, Depth, Alpha, Beta, Player, ChildVal),
    NewBeta is min(Beta, ChildVal),
    (   Alpha >= NewBeta
    ->  Val = NewBeta
    ;   minimize(Moves, State, Depth, Alpha, NewBeta, Player, Val)
    ).

utility(State, Player, Val) :-
    game_result(State, Winner), !,
    terminal_value(Winner, Player, 0, Val).
utility(state(Board, _), Player, Val) :-
    heuristic(Board, DefVal),
    (Player = defender -> Val = DefVal ; Val is -DefVal).

terminal_value(Player, Player, Depth, Val) :- !, Val is 100000 + (Depth * 100).
terminal_value(_, _, Depth, Val) :- Val is -100000 - (Depth * 100).

% board evaluation function for non-terminal states
heuristic(Board, Val) :-
    count_piece(Board, a, NumA),
    count_piece(Board, d, NumD),
    king_dist_to_corner(Board, KDist),
    piece_at(Board, KR, KC, k),
    count_blocking_sides(Board, KR, KC, KDanger),
    Val is (NumD * 10) - (NumA * 10) - (KDist * 5) - (KDanger * 15).

count_piece(Board, Piece, Count) :-
    include(is_piece(Piece), Board, Ps),
    length(Ps, Count).

is_piece(Piece, piece(Piece, _, _)).

king_dist_to_corner(Board, Dist) :-
    piece_at(Board, R, C, k),
    findall(D, (corner(CR, CC), D is abs(R-CR) + abs(C-CC)), Ds),
    min_list(Ds, Dist).

% --------------------------------------------------
% JSON interface (Python GUI)
% --------------------------------------------------

board_to_string(Board, Str) :-
    findall(S,
        (between(1, 11, R), between(1, 11, C), square_symbol(Board, R, C, S)),
        Syms),
    atomic_list_concat(Syms, '', Str).

square_symbol(Board, R, C, S) :-
    piece_at(Board, R, C, P), !,
    piece_symbol(P, S).
square_symbol(_, _, _, '.').

string_to_board(Str, Board) :-
    string_chars(Str, Chars),
    length(Chars, 121),
    chars_to_pieces(Chars, 1, Board).

chars_to_pieces([], _, []).
chars_to_pieces([Ch|Chars], Idx, Board) :-
    R is ((Idx - 1) // 11) + 1,
    C is ((Idx - 1) mod 11) + 1,
    Idx1 is Idx + 1,
    (   symbol_piece(Ch, P)
    ->  Board = [piece(P, R, C)|Rest]
    ;   Ch = '.'
    ->  Board = Rest
    ),
    chars_to_pieces(Chars, Idx1, Rest).

state_from_args(BoardStr, TurnStr, state(Board, Turn)) :-
    string_to_board(BoardStr, Board),
    atom_string(Turn, TurnStr),
    member(Turn, [attacker, defender]).

state_json(State) :-
    State = state(Board, Turn),
    board_to_string(Board, BoardStr),
    write('{'),
    write('"ok":true,'),
    json_pair_string('board', BoardStr), write(','),
    json_pair_atom('turn', Turn), write(','),
    write('"result":'), write_result(State), write(','),
    write('"difficulties":{"Easy":1,"Medium":3,"Hard":5}'),
    write('}').

write_result(State) :-
    (   game_result(State, Winner)
    ->  json_string(Winner)
    ;   write('null')
    ).

targets_json(Targets) :-
    write('{"ok":true,"targets":['),
    write_pairs(Targets),
    write(']}').

best_json(Move, Val, StateAfter) :-
    write('{'),
    write('"ok":true,'),
    write('"move":'), write_move(Move), write(','),
    format('"value":~w,', [Val]),
    StateAfter = state(Board, Turn),
    board_to_string(Board, BoardStr),
    json_pair_string('board', BoardStr), write(','),
    json_pair_atom('turn', Turn), write(','),
    write('"result":'), write_result(StateAfter),
    write('}').

error_json(Msg) :-
    write('{"ok":false,"error":'),
    json_string(Msg),
    write('}').

json_pair_string(K, V) :-
    json_string(K), write(':'), json_string(V).

json_pair_atom(K, V) :-
    atom_string(V, S), json_pair_string(K, S).

json_string(V) :- format('"~w"', [V]).

write_pairs([]).
write_pairs([[R,C]]) :- format('[~w,~w]', [R, C]).
write_pairs([[R,C]|Rest]) :- format('[~w,~w],', [R, C]), write_pairs(Rest).

write_move(move(FR, FC, TR, TC)) :- format('[~w,~w,~w,~w]', [FR, FC, TR, TC]).

arg_string(A, A) :- string(A), !.
arg_string(A, S) :- atom_string(A, S).

dispatch(["initial"]) :-
    initial_board(Board),
    state_json(state(Board, attacker)).
dispatch(["state", BS, TS]) :-
    state_from_args(BS, TS, State),
    state_json(State).
dispatch(["targets", BS, TS, RS, CS]) :-
    state_from_args(BS, TS, State),
    number_string(R, RS), number_string(C, CS),
    legal_targets(State, R, C, Targets),
    targets_json(Targets).
dispatch(["apply", BS, TS, FRS, FCS, TRS, TCS]) :-
    state_from_args(BS, TS, State),
    number_string(FR, FRS), number_string(FC, FCS),
    number_string(TR, TRS), number_string(TC, TCS),
    Move = move(FR, FC, TR, TC),
    (   legal_move(State, Move)
    ->  make_move(State, Move, StateAfter),
        state_json(StateAfter)
    ;   error_json('Illegal move')
    ).
dispatch(["best", BS, TS, DS]) :-
    state_from_args(BS, TS, State),
    number_string(Depth, DS),
    (   best_move(State, Depth, Move, Val)
    ->  make_move(State, Move, StateAfter),
        best_json(Move, Val, StateAfter)
    ;   error_json('No legal moves')
    ).
dispatch(_) :-
    error_json('Unknown command').

main :-
    current_prolog_flag(argv, Args),
    maplist(arg_string, Args, SArgs),
    dispatch(SArgs).

:- initialization(main, main).
