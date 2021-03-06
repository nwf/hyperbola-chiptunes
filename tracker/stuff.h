#include <progenv/types.h>
#include <progenv/trackerfmt.h>

struct trackline {
	u8	note;
	u8	instr;
	u8	cmd[2];
	u8	param[2];
	};

struct track {
	struct trackline	line[TRACKLEN];
};


void initchip();
u8 interrupthandler();

void readsong(int pos, int ch, u8 *dest);
void readtrack(int num, int pos, struct trackline *tl);
void readinstr(int num, int pos, u8 *il);

void silence();
void iedplonk(int, int);

void initgui();
void guiloop();

void startplaysong(int);
void startplaytrack(int);
void loadfile(char *);

extern u8 trackpos;
extern u8 playtrack;
extern u8 playsong;
extern u8 songpos;
extern int songlen;
