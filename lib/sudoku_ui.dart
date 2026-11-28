import 'package:flutter/material.dart';

const _root = 'assets/kotohoggle';
const sudokuInk = Color(0xFF593A28);
const sudokuPaper = Color(0xFFFFF8E8);
const sudokuGiven = Color(0xFFF3E1C2);
const sudokuRule = Color(0xFFB28B62);

const sudokuBackground = BoxDecoration(
  color: sudokuPaper,
  image: DecorationImage(
    image: AssetImage('$_root/sudoku_bg_paper.webp'),
    fit: BoxFit.fill,
  ),
);

class SudokuPaperBackground extends StatelessWidget {
  const SudokuPaperBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: sudokuBackground,
    child: SizedBox.expand(child: child),
  );
}

// The arrow is painted on the asset; Flutter supplies its hit target.
PreferredSizeWidget sudokuAppBar(BuildContext context, String title) {
  final width = MediaQuery.sizeOf(context).width;
  return AppBar(
    toolbarHeight: 64,
    titleSpacing: 0,
    leadingWidth: (width * .20).clamp(48.0, width).toDouble(),
    elevation: 0,
    backgroundColor: const Color(0xFF87482D),
    foregroundColor: const Color(0xFFFFF1D5),
    flexibleSpace: const SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(image: DecorationImage(
          image: AssetImage('$_root/sudoku_header_wood.webp'),
          fit: BoxFit.fill,
        )),
        child: SizedBox.expand(),
      ),
    ),
    leading: IconButton(
      tooltip: 'もどる',
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back, color: Colors.transparent),
    ),
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w900, fontSize: 23, color: Color(0xFFFFEBCB),
        shadows: [Shadow(color: Color(0xFF482614), offset: Offset(1, 2), blurRadius: 2)],
      )),
  );
}

// Frame replaces page padding; the actual board and effects stay inside.
class SudokuBoardFrame extends StatelessWidget {
  const SudokuBoardFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(image: DecorationImage(
      image: AssetImage('$_root/sudoku_board_frame.webp'),
      fit: BoxFit.fill,
    )),
    child: Padding(padding: const EdgeInsets.all(8), child: child),
  );
}

class SudokuInfoPanel extends StatelessWidget {
  const SudokuInfoPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(image: DecorationImage(
      image: AssetImage('$_root/sudoku_info_panel.webp'),
      fit: BoxFit.fill,
    )),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: child,
    ),
  );
}

ButtonStyle sudokuDigitStyle() => FilledButton.styleFrom(
  padding: EdgeInsets.zero,
  minimumSize: const Size(48, 48),
  backgroundColor: Colors.transparent,
  disabledBackgroundColor: Colors.transparent,
  foregroundColor: sudokuInk,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
);

class SudokuDigitFace extends StatelessWidget {
  const SudokuDigitFace({super.key, required this.digit, required this.enabled});
  final int digit;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$digit',
    child: Opacity(
      opacity: enabled ? 1 : .42,
      child: Image.asset('$_root/sudoku_num_button_$digit.webp',
        width: 48, height: 48, fit: BoxFit.contain, excludeFromSemantics: true),
    ),
  );
}

class SudokuProgressBar extends StatelessWidget {
  const SudokuProgressBar({super.key, required this.completed, required this.total});
  final int completed;
  final int total;
  @override
  Widget build(BuildContext context) {
    if (total <= 0 || completed < 0 || completed > total) {
      throw ArgumentError('Invalid sudoku progress: $completed/$total');
    }
    final fraction = completed / total;
    return Semantics(
      label: '進み具合 $completed / $total',
      child: SizedBox(height: 24, child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final leafWidth = width < 24 ? width : 24.0;
          return Stack(alignment: Alignment.centerLeft, children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF9B694D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sudokuInk, width: 1.5),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(borderRadius: BorderRadius.circular(5),
                child: LayoutBuilder(builder: (context, track) => Stack(
                  children: [
                    Positioned(left: 0, top: 0, bottom: 0,
                      width: track.maxWidth * fraction,
                      child: const DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Color(0xFFE57C96), Color(0xFFF4AF69),
                          Color(0xFFF7D76C), Color(0xFFA9CA78), Color(0xFF74B9D3),
                        ]),
                      )),
                    ),
                  ],
                )),
              ),
            ),
            Positioned(left: (width - leafWidth) * fraction,
              child: Image.asset('assets/story/kotohogu_story_ui/story_progress_leaf.png',
                width: leafWidth, height: 24, fit: BoxFit.contain,
                excludeFromSemantics: true)),
          ]);
        },
      )),
    );
  }
}
