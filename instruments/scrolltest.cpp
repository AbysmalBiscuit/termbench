/* Does a terminal stall because it is scrolling, or because it is moving
   bytes?

   termbench cannot answer that on its own: its two scrolling tests also push
   the most data, so scrolling and volume are confounded. This pushes an
   identical byte count through payloads that differ in one respect at a time.

   Modes, in increasing distance from termbench:

     manyline   1 char in 27 is '\n', nothing else. Byte-for-byte the payload
                termbench's ManyLine builds (termbench.cpp:229).
     longline   random letters only, no newlines and no escapes. Byte-for-byte
                termbench's LongLine (termbench.cpp:248). Wraps and scrolls
                only because the grid runs out of columns.
     scroll     longline plus one ESC [ m per screenful. Reset SGR is a no-op
                that leaves the cursor alone, so it still wraps and scrolls.
     noscroll   the same, with ESC [ H instead: cursor home, so each screenful
                overwrites the last and the terminal never scrolls.

   scroll and noscroll are the pair that isolates scrolling: same length, same
   write sizes, same character distribution, same parser work to within one
   escape per screen. If only scroll stalls, scrolling causes it. If both
   stall, volume does.

   The trailing text/binary argument is the one that turned out to matter most.
   In text mode the UCRT chops every _write into its own ~5 KiB WriteFile calls
   whatever chunkMB says, so the kernel-level write size is never what the
   caller asked for. termbench calls _setmode(1, _O_BINARY) (termbench.cpp:372)
   and so issues one WriteFile per write. Pass "binary" to match it.

   Results go to a file rather than stdout, because stdout has to stay
   attached to the terminal or the measurement is of a pipe.

   Build:
     zig c++ -O3 scrolltest.cpp -o scrolltest.exe
   Run:
     scrolltest.exe manyline 1024 158 41 out.txt 64 binary
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

enum mode { Mode_ManyLine, Mode_LongLine, Mode_Scroll, Mode_NoScroll };

int main(int ArgCount, char **Args) {
    if (ArgCount < 6) {
        fprintf(stderr,
                "usage: scrolltest <manyline|longline|scroll|noscroll> <MB> <cols> <rows>\n"
                "                  <resultfile> [chunkMB] [text|binary]\n"
                "  manyline  1-in-27 newlines, matching termbench ManyLine\n"
                "  longline  letters only, matching termbench LongLine\n"
                "  scroll    longline plus ESC[m per screen (still scrolls)\n"
                "  noscroll  longline plus ESC[H per screen (never scrolls)\n"
                "  chunkMB defaults to 1. termbench writes 64 MB per call\n"
                "  (termbench.cpp:128).\n"
                "  text (default) leaves stdout as inherited, so the UCRT splits\n"
                "  every write into ~5 KiB WriteFile calls. binary matches\n"
                "  termbench and issues one WriteFile per write.\n");
        return 1;
    }

    mode Mode;
    if (strcmp(Args[1], "manyline") == 0)      Mode = Mode_ManyLine;
    else if (strcmp(Args[1], "longline") == 0) Mode = Mode_LongLine;
    else if (strcmp(Args[1], "scroll") == 0)   Mode = Mode_Scroll;
    else if (strcmp(Args[1], "noscroll") == 0) Mode = Mode_NoScroll;
    else {
        fprintf(stderr, "mode must be manyline, longline, scroll or noscroll\n");
        return 1;
    }

    size_t TotalMB = (size_t)atoll(Args[2]);
    int Cols = atoi(Args[3]);
    int Rows = atoi(Args[4]);
    const char *ResultPath = Args[5];
    size_t ChunkMB = (ArgCount > 6) ? (size_t)atoll(Args[6]) : 1;

    const char *StdioName = (ArgCount > 7) ? Args[7] : "text";
    bool Binary = (strcmp(StdioName, "binary") == 0);
    if (!Binary && strcmp(StdioName, "text") != 0) {
        fprintf(stderr, "last argument must be 'text' or 'binary'\n");
        return 1;
    }

    if (TotalMB == 0 || Cols <= 0 || Rows <= 0 || ChunkMB == 0) {
        fprintf(stderr, "MB, cols, rows and chunkMB must all be positive\n");
        return 1;
    }
    if (ChunkMB > TotalMB) ChunkMB = TotalMB;

    size_t ChunkSize = ChunkMB * 1024 * 1024;

    // Stop short of the last cell so the noscroll payload cannot trip a
    // deferred wrap on the final column and scroll anyway.
    size_t ScreenChars = (size_t)Cols * (size_t)Rows - 10;
    if (ScreenChars < 16) {
        fprintf(stderr, "grid too small\n");
        return 1;
    }

    char *Chunk = (char *)malloc(ChunkSize);
    if (!Chunk) { fprintf(stderr, "out of memory\n"); return 1; }

    srand(1);
    if (Mode == Mode_ManyLine) {
        int TotalCharCount = 27;
        for (size_t At = 0; At < ChunkSize; ++At) {
            char Pick = (char)(rand() % TotalCharCount);
            Chunk[At] = (Pick == 26) ? '\n' : ('a' + Pick);
        }
    } else {
        for (size_t At = 0; At < ChunkSize; ++At) {
            Chunk[At] = 'a' + (char)(rand() % 26);
        }
        if (Mode == Mode_Scroll || Mode == Mode_NoScroll) {
            const char *Escape = (Mode == Mode_Scroll) ? "\x1b[m" : "\x1b[H";
            // Overwrite in place so every mode keeps an identical byte count.
            for (size_t At = ScreenChars; At + 3 <= ChunkSize; At += ScreenChars) {
                memcpy(Chunk + At, Escape, 3);
            }
        }
    }

    int Out = FILENO(stdout);
#if _WIN32
    if (Binary) _setmode(Out, _O_BINARY);
#endif

    size_t Target = TotalMB * 1024 * 1024;
    size_t Written = 0;
    // termbench counts requested bytes rather than returned ones
    // (termbench.cpp:148), so a short write would inflate its throughput and
    // not ours. Record the spread to find out whether that ever happens.
    size_t ShortWrites = 0, MinReturned = ChunkSize;

    auto Start = std::chrono::steady_clock::now();
    while (Written < Target) {
        int N = WRITE_FN(Out, Chunk, (unsigned int)ChunkSize);
        if (N <= 0) break;
        if ((size_t)N < ChunkSize) {
            ++ShortWrites;
            if ((size_t)N < MinReturned) MinReturned = (size_t)N;
        }
        Written += (size_t)N;
    }
    auto End = std::chrono::steady_clock::now();

    double Seconds = std::chrono::duration<double>(End - Start).count();
    double GBs = Seconds > 0.0 ? ((double)Written / (1024.0 * 1024.0 * 1024.0)) / Seconds : 0.0;

    FILE *F = fopen(ResultPath, "w");
    if (F) {
        fprintf(F,
                "mode=%s bytes=%zu seconds=%.4f gbs=%.4f grid=%dx%d chunkMB=%zu "
                "stdio=%s shortwrites=%zu minreturned=%zu\n",
                Args[1], Written, Seconds, GBs, Cols, Rows, ChunkMB,
                Binary ? "binary" : "text", ShortWrites, MinReturned);
        fclose(F);
    }

    free(Chunk);
    return 0;
}
