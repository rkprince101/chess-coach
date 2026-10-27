import 'package:dartchess/dartchess.dart';

import '../models/lesson.dart';

/// The built-in curriculum. Every position and line is checked by
/// `test/lessons_test.dart`, so a typo here fails the test suite rather than
/// confusing a student.
const List<Lesson> lessons = [
  // ---------------------------------------------------------------------------
  // Basics
  Lesson(
    id: 'board',
    title: 'Meet the board',
    category: LessonCategory.basics,
    summary: 'Files, ranks, square names and the starting position.',
    steps: [
      LessonStep(
        title: 'The battlefield',
        fen: kInitialFEN,
        text:
            'The board has 64 squares in an 8 by 8 grid. Columns are called files and are lettered a to h from White\'s left. Rows are called ranks and are numbered 1 to 8 starting from White\'s side. Every square has a name made of its file and rank, like e4 or g7.\n\nSet-up check: the bottom-right corner square (h1) must be light, and each queen starts on her own colour: the white queen on the light square d1, the black queen on the dark square d8. White always moves first.',
        goal: GoalType.read,
        highlights: [Square.d1, Square.d8, Square.h1],
      ),
    ],
  ),
  Lesson(
    id: 'pawn',
    title: 'The pawn',
    category: LessonCategory.basics,
    summary: 'Moves forward, captures diagonally, never goes back.',
    steps: [
      LessonStep(
        title: 'Marching forward',
        fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
        text:
            'Pawns move straight ahead one square at a time, and never backwards. On its very first move a pawn may choose to advance two squares instead. Push the e-pawn two squares to e4.',
        goal: GoalType.playLine,
        line: ['e4'],
        highlights: [Square.e4],
        successText: 'That two-square leap is only available from the starting square. After that it is one step at a time.',
      ),
      LessonStep(
        title: 'Capturing',
        fen: '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1',
        text:
            'Pawns are the only pieces that capture differently from how they move: they capture one square diagonally forward. A pawn can never capture the piece directly in front of it, and if something blocks its path it simply cannot advance. Capture the black pawn on d5.',
        goal: GoalType.playLine,
        line: ['exd5'],
        successText: 'In notation a pawn capture is written with the file it came from: exd5.',
      ),
    ],
  ),
  Lesson(
    id: 'knight',
    title: 'The knight',
    category: LessonCategory.basics,
    summary: 'The L-shaped jumper that ignores blockers.',
    steps: [
      LessonStep(
        title: 'The L-shape',
        fen: '4k3/8/8/8/8/8/8/4K1N1 w - - 0 1',
        text:
            'The knight moves in an L: two squares in one direction and then one square sideways. It is the only piece that can jump over other pieces, and it always lands on a square of the opposite colour to the one it left. Bring the knight from g1 to e5 in two moves.',
        goal: GoalType.reachSquare,
        targetSquare: Square.e5,
        maxMoves: 2,
        highlights: [Square.e5],
        successText: 'Knights love central squares like e5: from the centre they control eight squares, from a corner only two.',
      ),
      LessonStep(
        title: 'Knight tour',
        fen: '7k/3p4/8/4p3/8/5p2/8/K5N1 w - - 0 1',
        text:
            'Practice time. Capture all three black pawns with the knight. Plan the route before you move: which pawn is a knight-jump away right now?',
        goal: GoalType.captureAll,
        maxMoves: 5,
        successText: 'Nicely done. Seeing knight routes two or three jumps ahead is a real skill; it comes with practice.',
      ),
    ],
  ),
  Lesson(
    id: 'bishop',
    title: 'The bishop',
    category: LessonCategory.basics,
    summary: 'Long diagonals, one colour for life.',
    steps: [
      LessonStep(
        title: 'Diagonals',
        fen: '4k3/8/8/8/8/8/8/2B1K3 w - - 0 1',
        text:
            'Bishops slide any number of squares along a diagonal, but they cannot jump. Each side starts with one bishop on light squares and one on dark squares, and a bishop stays on its colour forever. Move the bishop to h6 in a single move.',
        goal: GoalType.reachSquare,
        targetSquare: Square.h6,
        maxMoves: 1,
        highlights: [Square.h6],
      ),
      LessonStep(
        title: 'Bishop sweep',
        fen: '4k3/8/7p/6p1/8/4p3/8/2B1K3 w - - 0 1',
        text: 'Capture all three black pawns with the bishop. Look for the diagonal that connects them.',
        goal: GoalType.captureAll,
        maxMoves: 5,
        successText: 'A bishop on a long open diagonal is a monster. Keep your bishops\' diagonals clear of your own pawns.',
      ),
    ],
  ),
  Lesson(
    id: 'rook',
    title: 'The rook',
    category: LessonCategory.basics,
    summary: 'Straight lines along files and ranks.',
    steps: [
      LessonStep(
        title: 'Files and ranks',
        fen: '7k/8/8/p3p3/8/4p3/8/R3K3 w - - 0 1',
        text:
            'Rooks move any distance horizontally or vertically. They are worth about five pawns, more than a knight or bishop. Capture all three black pawns with the rook.',
        goal: GoalType.captureAll,
        maxMoves: 5,
        successText: 'Rooks belong on open files, where no pawns block them, and on the seventh rank where they attack pawns from the side.',
      ),
    ],
  ),
  Lesson(
    id: 'queen',
    title: 'The queen',
    category: LessonCategory.basics,
    summary: 'Rook plus bishop: the most powerful piece.',
    steps: [
      LessonStep(
        title: 'All directions',
        fen: '7k/8/8/3p2p1/8/8/6p1/3QK3 w - - 0 1',
        text:
            'The queen combines the rook and the bishop: any distance in any straight line. She is worth about nine pawns, so losing her usually loses the game. Capture all three black pawns with the queen.',
        goal: GoalType.captureAll,
        maxMoves: 5,
        successText: 'Because the queen is so valuable, bringing her out too early lets the opponent develop pieces while chasing her. Patience.',
      ),
    ],
  ),
  Lesson(
    id: 'king',
    title: 'The king',
    category: LessonCategory.basics,
    summary: 'One square at a time, never into danger.',
    steps: [
      LessonStep(
        title: 'Careful steps',
        fen: '7k/8/2p5/8/8/3K4/8/5r2 w - - 0 1',
        text:
            'The king moves one square in any direction. It may never move onto a square attacked by an enemy piece, and the two kings can never stand next to each other. Walk the king from d3 to e5 in two moves. Watch out: the rook on f1 controls the whole f-file and the pawn on c6 guards d5.',
        goal: GoalType.reachSquare,
        targetSquare: Square.e5,
        maxMoves: 2,
        highlights: [Square.e5],
        successText: 'The king is a weak piece in the middlegame but a strong one in the endgame, when it should march to the centre.',
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // Special moves
  Lesson(
    id: 'castling',
    title: 'Castling',
    category: LessonCategory.specialMoves,
    summary: 'The only move where two pieces move at once.',
    steps: [
      LessonStep(
        title: 'Kingside',
        fen: 'r3k2r/pppq1ppp/2npbn2/4p3/2B1P3/2NP1N2/PPPBQPPP/R3K2R w KQkq - 0 1',
        text:
            'Castling tucks your king into safety and brings a rook toward the centre. The king moves two squares toward a rook and the rook jumps to the square the king crossed. Four conditions: the king and that rook have never moved, the squares between them are empty, the king is not in check, and the king does not pass through or land on an attacked square. Castle kingside now by moving the king from e1 to g1.',
        goal: GoalType.playLine,
        line: ['O-O'],
        arrows: [(Square.e1, Square.g1)],
        successText: 'Written O-O. Most games see both sides castle within the first ten moves.',
      ),
      LessonStep(
        title: 'Queenside',
        fen: 'r3k2r/ppp2ppp/2n1bn2/3qp3/3P4/2N1BN2/PPPQ1PPP/R3K2R w KQkq - 0 1',
        text:
            'You can also castle queenside (written O-O-O): the king goes to c1 and the rook from a1 lands on d1. It takes one move longer to prepare, because three squares must be empty, and the king ends up slightly less sheltered. Castle queenside now.',
        goal: GoalType.playLine,
        line: ['O-O-O'],
        arrows: [(Square.e1, Square.c1)],
      ),
      LessonStep(
        title: 'When castling is illegal',
        fen: '4k3/8/b7/8/8/8/8/4K2R w K - 0 1',
        text:
            'Here White would love to castle, but the bishop on a6 attacks f1, the square the king must cross. Castling through check is not allowed, so the board will not offer it. You also cannot castle while in check or after the king or rook has moved, even if they came back. Play any move to continue.',
        goal: GoalType.anyMove,
        arrows: [(Square.a6, Square.f1)],
      ),
    ],
  ),
  Lesson(
    id: 'en-passant',
    title: 'En passant',
    category: LessonCategory.specialMoves,
    summary: 'The pawn capture everyone forgets.',
    steps: [
      LessonStep(
        title: 'In passing',
        fen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
        text:
            'Black just pushed the d-pawn two squares from d7 to d5, sliding past your pawn on e5. For this one move only, you may capture it as if it had moved a single square: your pawn goes to d6 and the black pawn disappears. This is en passant, French for "in passing". If you wait a move, the right is gone. Capture en passant now.',
        goal: GoalType.playLine,
        line: ['exd6'],
        arrows: [(Square.e5, Square.d6)],
        successText: 'The rule exists so a pawn cannot use its double step to sneak past an enemy pawn without a fight.',
      ),
    ],
  ),
  Lesson(
    id: 'promotion',
    title: 'Promotion',
    category: LessonCategory.specialMoves,
    summary: 'Turn a pawn into a queen, or sometimes a knight.',
    steps: [
      LessonStep(
        title: 'Reaching the end',
        fen: '8/4P3/8/8/8/8/k7/4K3 w - - 0 1',
        text:
            'When a pawn reaches the last rank it must be replaced by a queen, rook, bishop or knight of the same colour, regardless of what you still have on the board. You can even have several queens. Push the pawn to e8 and promote it to a queen.',
        goal: GoalType.playLine,
        line: ['e8=Q'],
        successText: 'Written e8=Q. In the endgame, passed pawns that can no longer be stopped decide most games.',
      ),
      LessonStep(
        title: 'Underpromotion',
        fen: '8/2k1P3/5q2/8/8/8/8/6K1 w - - 0 1',
        text:
            'Queens are not always best. Here e8=Q gives you a queen, but Black already has one and the game would be roughly level. Look for a promotion that gives check and attacks the black queen at the same time; it wins the queen for nothing.',
        goal: GoalType.playLine,
        line: ['e8=N+'],
        successText: 'A knight fork on king and queen. Underpromoting to a knight is rare but decisive when it forks or gives a check the queen could not.',
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // Fundamentals
  Lesson(
    id: 'check-mate-stalemate',
    title: 'Check, checkmate and stalemate',
    category: LessonCategory.fundamentals,
    summary: 'How games end, and the draw trap to avoid.',
    steps: [
      LessonStep(
        title: 'Escaping check',
        fen: '4r1k1/8/8/8/8/8/8/4K3 w - - 0 1',
        text:
            'Check means the king is attacked. You must answer immediately in one of three ways: move the king, block the attack, or capture the attacker. Here the rook on e8 checks along the e-file and nothing can block or capture, so the king must step off the file. Play any legal move.',
        goal: GoalType.anyMove,
        arrows: [(Square.e8, Square.e1)],
      ),
      LessonStep(
        title: 'Checkmate',
        fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1',
        text:
            'Checkmate is a check the king cannot escape: the game is over. The black king is boxed in by its own pawns on the second rank, a classic "back rank" weakness. Deliver mate in one move.',
        goal: GoalType.checkmate,
        maxMoves: 1,
        successText: 'Ra8#. Remember this picture: a king stuck behind its own pawns is mated by a single rook or queen on the back rank.',
      ),
      LessonStep(
        title: 'Stalemate: the draw trap',
        fen: '7k/8/6K1/5Q2/8/8/8/8 w - - 0 1',
        text:
            'Stalemate happens when the side to move is NOT in check but has no legal move at all. It is a draw, no matter how much material you are ahead. With a queen and king against a lone king you must give mate without accidentally taking away every square. Find the checkmate in one; be careful, one tempting queen move here is stalemate.',
        goal: GoalType.checkmate,
        maxMoves: 1,
        successText: 'Before any quiet move in a winning endgame, ask: does my opponent still have a legal move?',
      ),
    ],
  ),
  Lesson(
    id: 'piece-values',
    title: 'Piece values and trades',
    category: LessonCategory.fundamentals,
    summary: 'Count before you capture.',
    steps: [
      LessonStep(
        title: 'The exchange rate',
        fen: '4k3/8/8/1p1q4/8/2N5/8/4K3 w - - 0 1',
        text:
            'A rough scale: pawn 1, knight 3, bishop 3, rook 5, queen 9, king priceless. Use it to judge trades: giving a knight for a rook (the "exchange") wins two points; giving a rook for a bishop loses two. Your knight on c3 can take either the pawn on b5 or the queen on d5. Choose.',
        goal: GoalType.playLine,
        line: ['Nxd5'],
        successText: 'Always look at every capture available to both sides before you move. Free material is the most common way games are decided at club level.',
      ),
    ],
  ),
  Lesson(
    id: 'opening-principles',
    title: 'Opening principles',
    category: LessonCategory.fundamentals,
    summary: 'Centre, development, king safety.',
    steps: [
      LessonStep(
        title: 'The three goals',
        fen: kInitialFEN,
        text:
            'You do not need to memorise openings to play them well. Follow three goals in the first ten moves: 1) Control the centre with pawns on e4/d4 (or e5/d5) because pieces are strongest there. 2) Develop knights and bishops off the back rank, knights before bishops, each piece moving once. 3) Castle early and connect your rooks.\n\nAvoid: moving the same piece twice, bringing the queen out early, grabbing pawns on the edge, and moving the f-pawn, which weakens your king.\n\nThe best practice is a real game. Start one from the Play screen; the coach will point out each principle as it comes up.',
        goal: GoalType.read,
        highlights: [Square.e4, Square.d4, Square.e5, Square.d5],
      ),
      LessonStep(
        title: 'A model start',
        fen: kInitialFEN,
        text: 'Play through a model opening as White. After each of your moves a short note explains the idea.',
        goal: GoalType.playLine,
        line: ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'O-O', 'Nf6', 'd3', 'd6', 'Nc3'],
        notes: [
          'e4 stakes a claim in the centre and opens lines for the queen and the f1 bishop.',
          null,
          'Nf3 develops a piece toward the centre and attacks the e5 pawn: development with a threat.',
          null,
          'Bc4 aims at f7, the weakest square around the black king, and prepares castling.',
          null,
          'King safe, rook closer to the centre. Now every piece can join the fight.',
          null,
          'd3 supports e4 and opens the diagonal for the c1 bishop. Modest but solid.',
          null,
          'Nc3 completes minor-piece development. Notice: no piece moved twice, queen still at home, king castled.',
        ],
        successText: 'That is the Italian Game. Both sides followed the principles and reached a healthy position.',
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // Tactics
  Lesson(
    id: 'fork',
    title: 'The fork',
    category: LessonCategory.tactics,
    summary: 'One piece, two targets.',
    steps: [
      LessonStep(
        title: 'Knight fork',
        fen: '8/2k3q1/8/8/3N4/8/8/4K3 w - - 0 1',
        text:
            'A fork attacks two things at once, so the opponent can only save one. Knights are the best forkers because their attack is hard to see and cannot be blocked. Find the knight move that attacks both the king and the queen.',
        goal: GoalType.playLine,
        line: ['Ne6+'],
        successText: 'Ne6+ hits the king on c7 and the queen on g7. Black must move the king and the queen falls. A fork with check is called a royal fork.',
      ),
      LessonStep(
        title: 'Pawn fork',
        fen: '6k1/8/2n1b3/8/2PP4/8/8/6K1 w - - 0 1',
        text:
            'Even a humble pawn forks. Two black pieces sit on the same rank one square apart, a classic pawn-fork pattern. Advance a pawn so it attacks both; make sure the forking pawn is protected, or it will simply be captured.',
        goal: GoalType.playLine,
        line: ['d5'],
        successText: 'd5 attacks the knight on c6 and the bishop on e6. Whatever moves, the other is lost for a pawn.',
      ),
    ],
  ),
  Lesson(
    id: 'pin',
    title: 'The pin',
    category: LessonCategory.tactics,
    summary: 'A piece that cannot move without exposing something worse.',
    steps: [
      LessonStep(
        title: 'Absolute pin',
        fen: '4k3/pp6/2n5/1B6/3P4/8/8/6K1 w - - 0 1',
        text:
            'The bishop on b5 pins the knight on c6 to the king on e8: the knight cannot legally move because it would expose the king. This is an absolute pin. Taking it at once with the bishop only trades, because the b7 pawn recaptures. A pinned piece is a sitting target, so attack it again with something cheaper. Find the move.',
        goal: GoalType.playLine,
        line: ['d5'],
        arrows: [(Square.b5, Square.e8)],
        successText: 'd5 attacks the pinned knight a second time and it cannot run. Rule of thumb: pin, then pile up.',
      ),
    ],
  ),
  Lesson(
    id: 'skewer',
    title: 'The skewer',
    category: LessonCategory.tactics,
    summary: 'A pin in reverse: the valuable piece is in front.',
    steps: [
      LessonStep(
        title: 'X-ray attack',
        fen: '8/4q3/8/8/4k3/8/8/R5K1 w - - 0 1',
        text:
            'In a skewer the more valuable piece stands in front and must move, exposing the piece behind it. The black king and queen share the e-file. Give check along that file.',
        goal: GoalType.playLine,
        line: ['Re1+'],
        arrows: [(Square.e4, Square.e7)],
        successText: 'After Re1+ the king must step aside and the rook takes the queen. Kings and queens on the same line are always worth a second look.',
      ),
    ],
  ),
  Lesson(
    id: 'discovered-attack',
    title: 'Discovered attack',
    category: LessonCategory.tactics,
    summary: 'Move one piece to unleash another.',
    steps: [
      LessonStep(
        title: 'Discovered check',
        fen: '3qk3/5pp1/8/4N3/8/8/8/4R1K1 w - - 0 1',
        text:
            'When a piece moves out of the way of a friendly rook, bishop or queen, the piece behind attacks "by discovery". If that hidden attack is a check, the moving piece can do anything it likes, because the opponent must deal with the check first. Move the knight so the rook gives check while the knight attacks the queen.',
        goal: GoalType.playLine,
        line: ['Nc6+'],
        arrows: [(Square.e1, Square.e8)],
        successText: 'Nc6+ is discovered check from the rook, and the knight attacks d8. Black must save the king, so the queen is lost. If the moving piece also gives check it is a double check, which can only be answered by a king move.',
      ),
    ],
  ),
  Lesson(
    id: 'back-rank',
    title: 'Back-rank mate',
    category: LessonCategory.tactics,
    summary: 'The most common mate in amateur chess.',
    steps: [
      LessonStep(
        title: 'The pattern',
        fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1',
        text:
            'When a castled king has not made an escape square (luft) in front of it, a single heavy piece on the back rank is mate. Deliver it.',
        goal: GoalType.checkmate,
        maxMoves: 1,
      ),
      LessonStep(
        title: 'Breaking through',
        fen: '3qr1k1/5ppp/8/8/8/8/4QPPP/4R1K1 w - - 0 1',
        text:
            'Black has guarded the back rank with a rook and a queen. But a defender can be overloaded: the queen must recapture on e8, and then it is the rook\'s turn. Sacrifice the queen to force mate in two.',
        goal: GoalType.playLine,
        line: ['Qxe8+', 'Qxe8', 'Rxe8#'],
        notes: [
          'The queen is deflecting the defender. Black is forced to recapture.',
          null,
          'And the rook finishes the job.',
        ],
        successText: 'Whenever the enemy king has no luft, count your attackers against their defenders on the back rank.',
      ),
    ],
  ),
  Lesson(
    id: 'smothered-mate',
    title: 'Smothered mate',
    category: LessonCategory.tactics,
    summary: 'A king suffocated by its own pieces.',
    steps: [
      LessonStep(
        title: 'The knight strikes',
        fen: '6rk/6pp/8/4N3/8/8/8/6K1 w - - 0 1',
        text:
            'The black king on h8 is surrounded by its own rook and pawns. Only a knight can attack a square without being blocked, so only a knight can mate here. Find it.',
        goal: GoalType.checkmate,
        maxMoves: 1,
        successText: 'Nf7#. The full version, where a queen sacrifice on g8 forces the rook to smother the king, is called Philidor\'s Legacy.',
      ),
    ],
  ),
  Lesson(
    id: 'remove-defender',
    title: 'Removing the defender',
    category: LessonCategory.tactics,
    summary: 'Capture the guard, then take the prize.',
    steps: [
      LessonStep(
        title: 'Who guards h7?',
        fen: '5rk1/5ppp/5n2/6BQ/8/3B4/8/6K1 w - - 0 1',
        text:
            'The queen on h5 and the bishop on d3 both aim at h7, but the knight on f6 defends it. When a single piece holds a position together, remove it. Start the combination.',
        goal: GoalType.playLine,
        line: ['Bxf6', 'gxf6', 'Qxh7#'],
        notes: [
          'The defender is gone. If Black recaptures, h7 falls with mate; if not, Black is simply a piece down.',
          null,
          'Mate. Ask of every defended target: who is guarding it, and can that guard be captured, driven away or overloaded?',
        ],
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // Checkmates and endgames
  Lesson(
    id: 'ladder-mate',
    title: 'Ladder mate with two rooks',
    category: LessonCategory.checkmates,
    summary: 'Push the king to the edge rank by rank.',
    steps: [
      LessonStep(
        title: 'Climb the ladder',
        fen: '8/8/8/4k3/8/8/8/RR4K1 w - - 0 1',
        text:
            'Two rooks mate without any help from the king. Give check with one rook to take away a rank, then check with the other rook on the next rank, alternating like rungs of a ladder. If the king approaches a rook, move that rook to the far side of the board first. Checkmate the black king.',
        goal: GoalType.checkmate,
        maxMoves: 12,
        successText: 'The ladder (or lawnmower) mate. The same idea works with a queen and a rook.',
      ),
    ],
  ),
  Lesson(
    id: 'queen-mate',
    title: 'King and queen vs king',
    category: LessonCategory.checkmates,
    summary: 'The essential mate every player must know.',
    steps: [
      LessonStep(
        title: 'The box method',
        fen: '8/8/8/4k3/8/8/8/3QK3 w - - 0 1',
        text:
            'Use the queen to build a box around the enemy king and shrink it a knight\'s move away from the king, never giving check. When the king is on the edge, bring your own king up to support the queen and mate. Danger: do not take away the king\'s last square unless it is mate; that is stalemate. Checkmate the black king.',
        goal: GoalType.checkmate,
        maxMoves: 20,
        successText: 'Excellent. With good technique this takes at most ten moves from anywhere.',
      ),
    ],
  ),
  Lesson(
    id: 'rook-mate',
    title: 'King and rook vs king',
    category: LessonCategory.checkmates,
    summary: 'Cut off, take the opposition, check.',
    steps: [
      LessonStep(
        title: 'Cut and push',
        fen: '8/8/8/4k3/8/8/8/R3K3 w - - 0 1',
        text:
            'The rook cuts the king off along a rank or file; your king walks up to stand directly opposite the enemy king (the opposition); then a rook check forces it back one line. When the enemy king would step toward your rook, make a waiting move with the rook along its line. Repeat until the king is mated on the edge. Checkmate the black king.',
        goal: GoalType.checkmate,
        maxMoves: 30,
        successText: 'Well played. The rook mate is slower than the queen mate but the ideas of cutting off and opposition appear in every endgame.',
      ),
    ],
  ),
  Lesson(
    id: 'pawn-endgame',
    title: 'King and pawn: the opposition',
    category: LessonCategory.checkmates,
    summary: 'Win the race to promote.',
    steps: [
      LessonStep(
        title: 'King in front',
        fen: '4k3/8/4K3/8/4P3/8/8/8 w - - 0 1',
        text:
            'With your king in front of the pawn you are winning, but only with care. Two rules: keep the king ahead of the pawn and take the opposition (kings facing each other with one square between, and the other side to move) so the enemy king must give way. Do not rush the pawn: a pawn on the seventh with the enemy king in front and your king beside it is a stalemate draw. Promote the pawn.',
        goal: GoalType.promote,
        maxMoves: 25,
        successText: 'You out-manoeuvred the defending king. The opposition is the single most important idea in pawn endgames.',
      ),
    ],
  ),

  // ---------------------------------------------------------------------------
  // Openings (guided tours)
  Lesson(
    id: 'italian',
    title: 'Italian Game',
    category: LessonCategory.openings,
    summary: 'The classical way to open: quick development, bishop on c4.',
    steps: [
      LessonStep(
        title: 'Giuoco Piano',
        fen: kInitialFEN,
        text: 'Play the white side of the Italian Game. After each move a note explains the plan.',
        goal: GoalType.playLine,
        line: ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'c3', 'Nf6', 'd4', 'exd4', 'cxd4', 'Bb4+', 'Nc3'],
        notes: [
          'Centre and open lines.',
          null,
          'Develop with a threat on e5.',
          null,
          'The Italian bishop eyes f7.',
          null,
          'c3 prepares d4 to build a big pawn centre.',
          null,
          'd4 challenges the centre now that c3 supports it.',
          null,
          'Recapture toward the centre; White has pawns on d4 and e4.',
          null,
          'Block the check with development. White has a strong centre and active pieces; Black will fight against it with ...Nxe4 ideas.',
        ],
        successText: 'This is the main line of the Giuoco Piano. Modern players also like the quiet 4.d3 followed by castling.',
      ),
    ],
  ),
  Lesson(
    id: 'ruy-lopez',
    title: 'Ruy Lopez',
    category: LessonCategory.openings,
    summary: 'The Spanish: pressure on e5 through the knight on c6.',
    steps: [
      LessonStep(
        title: 'Closed main line',
        fen: kInitialFEN,
        text: 'Play White in the Ruy Lopez, the most respected reply to 1...e5.',
        goal: GoalType.playLine,
        line: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6', 'O-O', 'Be7', 'Re1', 'b5', 'Bb3', 'd6', 'c3', 'O-O', 'h3'],
        notes: [
          null, null, null, null,
          'Bb5 attacks the knight that defends e5: indirect pressure on the centre.',
          null,
          'Keep the bishop; it will retreat to b3 and stay on the strong a2-g8 diagonal.',
          null,
          'Castle first, e4 is tactically safe for now.',
          null,
          'Re1 protects e4 and prepares the classic pawn structure.',
          null,
          'The bishop lands on its ideal square.',
          null,
          'c3 prepares d4 and gives the bishop a retreat on c2.',
          null,
          'h3 stops ...Bg4, which would pin the knight and pressure d4. A famous prophylactic move.',
        ],
        successText: 'The Closed Ruy Lopez. White plays d4 next and often manoeuvres the b1 knight to g3 via d2 and f1.',
      ),
    ],
  ),
  Lesson(
    id: 'qgd',
    title: "Queen's Gambit Declined",
    category: LessonCategory.openings,
    summary: 'Solid classical chess with 1.d4.',
    steps: [
      LessonStep(
        title: 'Orthodox Defence',
        fen: kInitialFEN,
        text: 'Play White in the Queen\'s Gambit. Note that c4 is not really a gambit: the pawn can always be regained.',
        goal: GoalType.playLine,
        line: ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5', 'Be7', 'e3', 'O-O', 'Nf3', 'Nbd7'],
        notes: [
          'd4 controls the centre and is protected by the queen, so it is harder to attack than e4.',
          null,
          'c4 pressures d5 and prepares to open the c-file.',
          null,
          'Develop and add pressure on d5.',
          null,
          'Bg5 pins the knight that defends d5.',
          null,
          'e3 supports d4 and opens the f1 bishop. Notice the c1 bishop got out before e3 closed it in.',
          null,
          'Nf3 completes development; Rc1 and Bd3 come next.',
          null,
        ],
        successText: 'A classical position. White\'s plan: Rc1, Bd3, castle, and a minority attack with b4-b5 or central play with e4.',
      ),
    ],
  ),
  Lesson(
    id: 'london',
    title: 'London System',
    category: LessonCategory.openings,
    summary: 'The same solid set-up against almost anything.',
    steps: [
      LessonStep(
        title: 'The set-up',
        fen: kInitialFEN,
        text: 'The London is popular because White reaches the same comfortable structure regardless of Black\'s replies. Play it.',
        goal: GoalType.playLine,
        line: ['d4', 'd5', 'Bf4', 'Nf6', 'e3', 'e6', 'Nf3', 'c5', 'c3', 'Nc6', 'Nbd2', 'Bd6', 'Bg3'],
        notes: [
          null, null,
          'Bf4 develops the bishop outside the pawn chain before e3 locks it in.',
          null,
          'e3 supports d4 and prepares Bd3.',
          null,
          null, null,
          'c3 builds the pyramid d4-e3-c3 and gives the bishop a retreat on c2 later.',
          null,
          'Nbd2 supports e4 ideas and keeps c3 for the pawn.',
          null,
          'Bg3 keeps the bishop; after ...Bxg3 hxg3 White gets an open h-file for the rook.',
        ],
        successText: 'Typical London: Bd3, O-O, then Ne5 and an attack on the kingside with f4 or Qf3.',
      ),
    ],
  ),
  Lesson(
    id: 'sicilian',
    title: 'Sicilian Defense (as Black)',
    category: LessonCategory.openings,
    summary: 'Fight for the win with 1...c5.',
    steps: [
      LessonStep(
        title: 'Najdorf',
        fen: kInitialFEN,
        text: 'Play Black. White opens 1.e4 and you answer with the Sicilian, trading your c-pawn for White\'s d-pawn to get an unbalanced game.',
        goal: GoalType.playLine,
        line: ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'],
        notes: [
          null,
          'c5 fights for d4 from the side and keeps the position asymmetrical.',
          null,
          'd6 controls e5 and prepares ...Nf6 without allowing e5.',
          null,
          'Take the centre pawn: Black now has two centre pawns against one.',
          null,
          'Nf6 attacks e4 and develops.',
          null,
          'a6 is the Najdorf move: it stops Nb5 and Bb5, and prepares ...e5 or ...b5.',
        ],
        successText: 'The Najdorf, favourite of Fischer and Kasparov. Plans: ...e5 or ...e6, ...b5, ...Bb7 and queenside play while White attacks on the kingside.',
      ),
    ],
  ),
  Lesson(
    id: 'french',
    title: 'French Defense (as Black)',
    category: LessonCategory.openings,
    summary: 'Solid pawn chains and a counterattack on d4.',
    steps: [
      LessonStep(
        title: 'Classical',
        fen: kInitialFEN,
        text: 'Play Black in the French. You accept a cramped light-squared bishop in exchange for a rock-solid centre and play against d4.',
        goal: GoalType.playLine,
        line: ['e4', 'e6', 'd4', 'd5', 'Nc3', 'Nf6', 'Bg5', 'Be7', 'e5', 'Nfd7'],
        notes: [
          null,
          'e6 prepares d5 so that the pawn on d5 is always supported.',
          null,
          'd5 challenges e4 at once.',
          null,
          'Nf6 adds pressure on e4.',
          null,
          'Be7 breaks the pin calmly.',
          null,
          'The knight retreats to d7; later ...c5 and ...f6 attack White\'s pawn chain at its base and its head.',
        ],
        successText: 'A Classical French. Black\'s plan: ...c5, ...Nc6, ...Qb6 against d4, and the freeing break ...f6.',
      ),
    ],
  ),
  Lesson(
    id: 'caro-kann',
    title: 'Caro-Kann Defense (as Black)',
    category: LessonCategory.openings,
    summary: 'Like the French, but the bishop gets out first.',
    steps: [
      LessonStep(
        title: 'Classical',
        fen: kInitialFEN,
        text: 'Play Black in the Caro-Kann, a favourite of players who like sound structures.',
        goal: GoalType.playLine,
        line: ['e4', 'c6', 'd4', 'd5', 'Nc3', 'dxe4', 'Nxe4', 'Bf5', 'Ng3', 'Bg6'],
        notes: [
          null,
          'c6 prepares d5 while keeping the c8 bishop\'s diagonal open, unlike the French.',
          null,
          'd5 challenges the centre.',
          null,
          'Exchange on e4 and gain time attacking the knight.',
          null,
          'Bf5 develops the "problem bishop" with tempo.',
          null,
          'Bg6 keeps the bishop safe; Black follows with ...Nd7, ...Ngf6, ...e6 and a very solid game.',
        ],
        successText: 'The Classical Caro-Kann. White usually plays h4-h5 to harass the bishop; Black answers ...h6 and castles queenside or kingside.',
      ),
    ],
  ),
  Lesson(
    id: 'kid',
    title: "King's Indian Defense (as Black)",
    category: LessonCategory.openings,
    summary: 'Give White the centre, then attack it.',
    steps: [
      LessonStep(
        title: 'Classical main line',
        fen: kInitialFEN,
        text: 'Play Black in the King\'s Indian, a fianchetto system that leads to sharp, opposite-wing attacks.',
        goal: GoalType.playLine,
        line: ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'Nf3', 'O-O', 'Be2', 'e5'],
        notes: [
          null,
          'Nf6 controls e4 and keeps options open.',
          null,
          'g6 prepares the fianchetto; the bishop on g7 will pressure d4 and e5 all game.',
          null,
          'The King\'s Indian bishop arrives.',
          null,
          'd6 supports a later ...e5 strike.',
          null,
          'Castle before opening the centre.',
          null,
          'e5 hits the centre. After d5 the centre locks and Black attacks on the kingside with ...f5 while White plays on the queenside.',
        ],
        successText: 'The Classical King\'s Indian. Expect fireworks: both sides attack the other\'s king.',
      ),
    ],
  ),
];

/// Topics for the AI concept library. The coach can teach anything typed in,
/// but these give students a map of the territory.
const Map<String, List<String>> conceptLibrary = {
  'Rules and basics': [
    'How each piece moves',
    'Castling rules',
    'En passant',
    'Pawn promotion and underpromotion',
    'Check, checkmate and stalemate',
    'Draw rules: repetition, fifty moves, insufficient material',
    'Algebraic notation',
    'Piece values and the exchange',
  ],
  'Tactics': [
    'Fork',
    'Pin',
    'Skewer',
    'Discovered attack and double check',
    'Removing the defender',
    'Deflection and decoy',
    'Overloading',
    'Zwischenzug (intermezzo)',
    'Interference',
    'X-ray attack',
    'Desperado',
    'Windmill',
    'Trapped pieces',
    'Zugzwang',
    'Perpetual check',
  ],
  'Checkmate patterns': [
    'Back-rank mate',
    'Smothered mate',
    "Scholar's mate and how to defend it",
    "Fool's mate",
    "Anastasia's mate",
    "Boden's mate",
    'Arabian mate',
    "Greco's mate",
    "Damiano's mate",
    'Epaulette mate',
    "Légal's mate",
    'Hook mate',
    'Opera mate',
  ],
  'Strategy': [
    'Opening principles',
    'Centre control',
    'Development and tempo',
    'King safety',
    'Pawn structure: doubled, isolated, backward pawns',
    'Passed pawns',
    'Weak squares and outposts',
    'Open files and the seventh rank',
    'Good bishop vs bad bishop',
    'Bishop pair',
    'Knight vs bishop',
    'Space advantage',
    'Prophylaxis',
    'Initiative',
    'Exchanging pieces when ahead',
    'Attacking the castled king',
    'Pawn storms and opposite-side castling',
    'Minority attack',
    'Isolated queen pawn positions',
  ],
  'Endgames': [
    'King and pawn endgames: opposition',
    'The square of the pawn',
    'Lucena position',
    'Philidor position',
    'Rook endgame principles',
    'Queen vs pawn on the seventh',
    'Bishop and knight mate',
    'Opposite-coloured bishops',
    'Activating the king in the endgame',
    'Triangulation',
  ],
  'Openings for White': [
    'Italian Game',
    'Ruy Lopez',
    'Scotch Game',
    'Vienna Game',
    "King's Gambit",
    "Queen's Gambit",
    'London System',
    'English Opening',
    'Réti Opening',
    'Catalan Opening',
  ],
  'Openings for Black': [
    'Sicilian Defense',
    'French Defense',
    'Caro-Kann Defense',
    'Scandinavian Defense',
    "Petrov's Defense",
    "King's Indian Defense",
    'Nimzo-Indian Defense',
    'Grünfeld Defense',
    'Slav Defense',
    'Dutch Defense',
    "Queen's Gambit Declined",
    "Queen's Gambit Accepted",
  ],
};
