/* Does a terminal stall on the bytes, or on the attribute changes inside them?

   termbench and scrolltest both push mostly-plain text: their payloads vary in
   volume and in whether the grid scrolls, never in how often the style of a
   cell changes. Real output is not like that. Syntax highlighting, ls --color,
   and any TUI emit an SGR every few cells, and a renderer that batches cells by
   style has nothing left to batch when every cell differs.

   This paints the same grid the same number of times in every mode and varies
   only how often an SGR precedes a cell.

   Modes, in increasing attribute density:

     plain      no escapes at all. The floor.
     perline    one truecolour foreground per row.
     stride     one foreground every N cells, N from the argument.
     percell    a foreground before every cell.
     percellbg  a foreground and a background before every cell.
     underline  percell plus underline on, which makes the terminal draw a
                decoration as well as a glyph.

   The colour changes at every SGR rather than repeating, so a terminal cannot
   skip the work by noticing the style is unchanged.

   The budget is screenfuls, not megabytes, which is the one place this departs
   from termbench and scrolltest. An SGR is bytes, so holding the byte count
   fixed would leave the dense modes painting a fraction of the screens the
   plain one paints -- at 158x41, percell is 18 bytes per cell against 1, so a
   fixed megabyte budget paints it 17 times less often. Rates from runs that
   painted different amounts of screen are not comparable, and the question here
   is what a screenful costs.

   So read fps first: it is the same work in every mode, and the ratio between
   modes is what the attributes cost. gbs is reported beside it because a
   terminal that is purely byte-bound holds gbs steady while fps collapses.

   Every screenful starts with ESC [ H, so the terminal repaints in place and
   never scrolls. Scrolling is the variable scrolltest isolates, not this one.

   Results go to a file rather than stdout, because stdout has to stay
   attached to the terminal or the measurement is of a pipe.

   Build:
     zig c++ -O3 sgrtest.cpp -o sgrtest.exe
   Run:
     sgrtest.exe percell 2000 158 41 out.txt 8 binary
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <chrono>

#if _WIN32
#include <io.h>
#include <fcntl.h>
#define WRITE_FN _write
#define FILENO _fileno
#else
#include <unistd.h>
#define WRITE_FN write
#define FILENO fileno
#endif

enum mode { Mode_Plain, Mode_PerLine, Mode_Stride, Mode_PerCell, Mode_PerCellBg, Mode_Underline };

/* Worst case per cell: two truecolour SGRs, an underline, and the character. */
#define MAX_BYTES_PER_CELL 48

struct payload {
    char *Bytes;
    size_t Length;
    size_t Cells;
};

/* One screenful: cursor home, then rows of cols cells, with SGRs at whatever
   density the mode asks for. */
static void AppendScreen(payload *Out, mode Mode, int Cols, int Rows, int Stride, int *Tick) {
    char *At = Out->Bytes + Out->Length;
    At += sprintf(At, "\x1b[H");
    if (Mode == Mode_Underline) At += sprintf(At, "\x1b[4m");
    for (int Y = 0; Y < Rows; ++Y) {
        if (Mode == Mode_PerLine) {
            At += sprintf(At, "\x1b[38;2;%d;%d;%dm", *Tick & 0xff, (*Tick * 7) & 0xff, 64);
            ++*Tick;
        }
        for (int X = 0; X < Cols; ++X) {
            bool Styled = Mode == Mode_PerCell || Mode == Mode_PerCellBg
                          || Mode == Mode_Underline
                          || (Mode == Mode_Stride && X % Stride == 0);
            if (Styled) {
                At += sprintf(At, "\x1b[38;2;%d;%d;%dm", *Tick & 0xff, (*Tick * 7) & 0xff, 64);
                if (Mode == Mode_PerCellBg) {
                    At += sprintf(At, "\x1b[48;2;%d;%d;%dm", (*Tick * 3) & 0xff, 32, 96);
                }
                ++*Tick;
            }
            *At++ = (char)(97 + (X + Y) % 26);
            ++Out->Cells;
        }
        /* No newline: the last column would wrap and scroll. Move instead. */
        if (Y + 1 < Rows) At += sprintf(At, "\x1b[%d;1H", Y + 2);
    }
    At += sprintf(At, "\x1b[m");
    Out->Length = (size_t)(At - Out->Bytes);
}

int main(int ArgCount, char **Args) {
    if (ArgCount < 6) {
        fprintf(stderr,
                "usage: sgrtest <plain|perline|stride|percell|percellbg|underline> <screens>\n"
                "               <cols> <rows> <resultfile> [stride] [text|binary]\n"
                "  plain      no escapes, the floor\n"
                "  perline    one truecolour foreground per row\n"
                "  stride     one foreground every N cells, N from [stride]\n"
                "  percell    a foreground before every cell\n"
                "  percellbg  a foreground and a background before every cell\n"
                "  underline  percell plus underline on\n"
                "  screens is the budget, so every mode paints the same grid the\n"
                "  same number of times. It rounds down to a whole write; the\n"
                "  result reports how many were actually painted.\n"
                "  stride defaults to 8 and is only read in stride mode.\n"
                "  text (default) leaves stdout as inherited, so the UCRT splits\n"
                "  every write into ~5 KiB WriteFile calls. binary matches\n"
                "  termbench and issues one WriteFile per write.\n");
        return 1;
    }

    mode Mode;
    if (strcmp(Args[1], "plain") == 0)           Mode = Mode_Plain;
    else if (strcmp(Args[1], "perline") == 0)    Mode = Mode_PerLine;
    else if (strcmp(Args[1], "stride") == 0)     Mode = Mode_Stride;
    else if (strcmp(Args[1], "percell") == 0)    Mode = Mode_PerCell;
    else if (strcmp(Args[1], "percellbg") == 0)  Mode = Mode_PerCellBg;
    else if (strcmp(Args[1], "underline") == 0)  Mode = Mode_Underline;
    else {
        fprintf(stderr, "unknown mode %s\n", Args[1]);
        return 1;
    }

    size_t TargetScreens = (size_t)atoll(Args[2]);
    int Cols = atoi(Args[3]);
    int Rows = atoi(Args[4]);
    const char *ResultPath = Args[5];
    int Stride = (ArgCount > 6) ? atoi(Args[6]) : 8;

    const char *StdioName = (ArgCount > 7) ? Args[7] : "text";
    bool Binary = (strcmp(StdioName, "binary") == 0);
    if (!Binary && strcmp(StdioName, "text") != 0) {
        fprintf(stderr, "last argument must be 'text' or 'binary'\n");
        return 1;
    }

    if (TargetScreens == 0 || Cols <= 0 || Rows <= 0 || Stride <= 0) {
        fprintf(stderr, "screens, cols, rows and stride must all be positive\n");
        return 1;
    }

    /* Around a megabyte per write, in whole screens so no write ends mid-row
       and every one of them repaints from the top. */
    size_t ScreenBytes = (size_t)Cols * (size_t)Rows * MAX_BYTES_PER_CELL + 64;
    size_t PerChunk = (1024 * 1024) / ScreenBytes;
    if (PerChunk == 0) PerChunk = 1;
    if (PerChunk > TargetScreens) PerChunk = TargetScreens;

    payload Chunk = {};
    Chunk.Bytes = (char *)malloc(PerChunk * ScreenBytes);
    if (!Chunk.Bytes) { fprintf(stderr, "out of memory\n"); return 1; }

    int Tick = 0;
    for (size_t I = 0; I < PerChunk; ++I) AppendScreen(&Chunk, Mode, Cols, Rows, Stride, &Tick);

    int Out = FILENO(stdout);
#if _WIN32
    if (Binary) _setmode(Out, _O_BINARY);
#endif

    size_t Writes = TargetScreens / PerChunk;
    size_t Written = 0, Screens = 0;
    size_t ShortWrites = 0, MinReturned = Chunk.Length;

    auto Start = std::chrono::steady_clock::now();
    for (size_t I = 0; I < Writes; ++I) {
        int N = WRITE_FN(Out, Chunk.Bytes, (unsigned int)Chunk.Length);
        if (N <= 0) break;
        if ((size_t)N < Chunk.Length) {
            ++ShortWrites;
            if ((size_t)N < MinReturned) MinReturned = (size_t)N;
        }
        Written += (size_t)N;
        /* A short write painted part of the buffer, so credit the screens in
           proportion rather than assuming they all landed. */
        Screens += PerChunk * (size_t)N / Chunk.Length;
    }
    auto End = std::chrono::steady_clock::now();

    double Seconds = std::chrono::duration<double>(End - Start).count();
    double GBs = Seconds > 0.0 ? ((double)Written / (1024.0 * 1024.0 * 1024.0)) / Seconds : 0.0;
    double Fps = Seconds > 0.0 ? (double)Screens / Seconds : 0.0;

    FILE *F = fopen(ResultPath, "w");
    if (F) {
        fprintf(F,
                "mode=%s screens=%zu bytes=%zu seconds=%.4f fps=%.1f gbs=%.4f "
                "bytespercell=%.2f grid=%dx%d stride=%d stdio=%s shortwrites=%zu "
                "minreturned=%zu\n",
                Args[1], Screens, Written, Seconds, Fps, GBs,
                (double)Chunk.Length / (double)Chunk.Cells, Cols, Rows, Stride,
                Binary ? "binary" : "text", ShortWrites, MinReturned);
        fclose(F);
    }

    free(Chunk.Bytes);
    return 0;
}
