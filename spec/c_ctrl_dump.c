// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
//
// c_ctrl_dump — the CONTROL plane built by the compiled libreac, on stdout, so
// the spec's generated parser can be asked to read it back.
//
// c_oracle_dump.c does this for the AUDIO layout: it dumps what libreac decodes
// and the harness compares numbers. This is the other half and it runs the
// other way round — libreac BUILDS, the ksy-generated parser READS, and the
// harness asserts they describe the same bytes. A shared constant catches a
// typo; a cross-parse catches a misunderstanding, and the control plane is
// where the misunderstandings have been.
//
// DEV-ONLY, like its sibling: it needs a libreac checkout and a C compiler that
// the spec repo does not otherwise depend on. See `make check-ctrl-oracle`.
//
//   c_ctrl_dump scene BODY          build all 343 transfer steps from an
//                                   8904-byte body; one 34-byte hex window
//                                   (frame[16:50]) per line
//   c_ctrl_dump scene-build MAC     reac_ctrl_scene_build()'s tag-only body,
//                                   as hex. REFUTED as a driver on real
//                                   hardware; dumped so the refutation stays a
//                                   measured thing rather than a claim.
//   c_ctrl_dump headamp CH P V      one DT1 head-amp record, checksums stamped
//                                   in the ONLY legal order
//   c_ctrl_dump headamp-badorder CH P V
//                                   the same record with the block stamped
//                                   BEFORE the record it encloses — the
//                                   ordering bug the library's contract exists
//                                   to prevent, emitted on purpose so a test
//                                   can watch the block checksum go bad
//   c_ctrl_dump verify              read 34-byte hex windows on stdin, print
//                                   one JSON object per line: what libreac's
//                                   verifiers say about each

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <reac/reac.h>
#include <reac/reac_ctrlblk.h>

/* libreac's own macros here, deliberately: this program must speak the
 * LIBRARY's numbers so the harness can compare them with the spec's. The
 * schema-vs-libreac constant check is a separate translation unit,
 * generated/reac_facts_assert.h. */

#define WIN 34   /* frame[16:50] — the type word plus the control block */

static int hexval(int c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static int unhex(const char *s, uint8_t *out, size_t cap)
{
	size_t n = 0;
	for (; s[0] && s[0] != '\n' && s[0] != '\r'; s += 2) {
		int hi = hexval(s[0]);
		int lo = s[1] ? hexval(s[1]) : -1;
		if (hi < 0 || lo < 0 || n >= cap)
			return -1;
		out[n++] = (uint8_t)((hi << 4) | lo);
	}
	return (int)n;
}

static void put_hex(const uint8_t *p, size_t n)
{
	for (size_t i = 0; i < n; i++)
		printf("%02x", p[i]);
	putchar('\n');
}

/* A DT1 head-amp record inside op 0403, laid out from the generated facts
 * rather than from remembered offsets. `stamp_record_first` is the contract:
 * the nested record sums to 0x80 and must be stamped BEFORE the block that
 * encloses it sums to 0, because a record fixed up afterwards invalidates the
 * block. Passing 0 emits exactly that bug. */
static void build_headamp(uint8_t win[WIN], int ch, int param, int value,
                          int stamp_record_first)
{
	const uint8_t op_len = 0x13;    /* record_len 6, data_len 3 */
	memset(win, 0, WIN);
	win[0] = (uint8_t)(0xcdu);
	win[1] = (uint8_t)(0xeau);
	win[2] = (uint8_t)(0x04u);
	win[3] = (uint8_t)(0x03u);
	win[4] = 0x00;
	win[5] = op_len;
	win[6] = 0x00; win[7] = 0x02; win[8] = 0x00; win[9] = 0xfe;  /* wrapper */
	win[10] = (uint8_t)(op_len - 5);                             /* len echo */
	win[11] = 0xf0;                                              /* SysEx     */
	win[12] = 0x41;                                              /* Roland    */
	win[13] = 0x0a;                                              /* device id */
	win[14] = 0x00; win[15] = 0x00; win[16] = 0x12;              /* model id  */
	win[17] = 0x12;                                              /* DT1       */
	win[18] = (uint8_t)(0x01u);
	win[19] = (uint8_t)(0x01u);
	win[20] = (uint8_t)ch;
	win[21] = (uint8_t)param;
	win[22] = (uint8_t)value;
	/* win[23] the record checksum, stamped below */
	win[24] = 0xf7;                                              /* SysEx end */

	if (stamp_record_first) {
		reac_ctrl_record_cksum_stamp(win + 18, 6);
		reac_ctrl_block_cksum_stamp(win + 2);
	} else {
		reac_ctrl_block_cksum_stamp(win + 2);
		reac_ctrl_record_cksum_stamp(win + 18, 6);
	}
}

static int cmd_scene(const char *path)
{
	static uint8_t body[REAC_SCENE_BYTES];
	FILE *f = fopen(path, "rb");
	if (!f) { perror(path); return 1; }
	size_t n = fread(body, 1, sizeof body, f);
	int extra = fgetc(f) != EOF;
	fclose(f);
	if (n != sizeof body || extra) {
		fprintf(stderr, "%s: want %d bytes, got %zu%s\n",
		        path, REAC_SCENE_BYTES, n, extra ? "+" : "");
		return 1;
	}
	for (int step = 0; step < REAC_SCENE_STEPS; step++) {
		uint8_t win[WIN];
		if (reac_ctrl_build_scene_step(win, body, sizeof body, step) != 0) {
			fprintf(stderr, "build_scene_step(%d) refused\n", step);
			return 1;
		}
		put_hex(win, WIN);
	}
	return 0;
}

static int cmd_scene_build(const char *macstr)
{
	static uint8_t body[REAC_SCENE_BYTES];
	uint8_t mac[6];
	unsigned v[6];
	if (sscanf(macstr, "%x:%x:%x:%x:%x:%x",
	           &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6) {
		fprintf(stderr, "a MAC is six colon-separated hex bytes\n");
		return 1;
	}
	for (int i = 0; i < 6; i++)
		mac[i] = (uint8_t)v[i];
	if (reac_ctrl_scene_build(body, sizeof body, mac) != 0) {
		fprintf(stderr, "scene_build refused\n");
		return 1;
	}
	put_hex(body, sizeof body);
	return 0;
}

static int cmd_verify(void)
{
	char line[8192];
	while (fgets(line, sizeof line, stdin)) {
		uint8_t win[WIN];
		int n = unhex(line, win, sizeof win);
		if (n != WIN) {
			fprintf(stderr, "want a %d-byte hex window, got %d\n", WIN, n);
			return 1;
		}
		/* reac_ctrl_checksum_verify() indexes frame[18:50]; a window is
		 * frame[16:50], so it sits 16 bytes into a scratch frame. */
		uint8_t frame[REAC_CTRL_BLOCK_END];
		memset(frame, 0, sizeof frame);
		memcpy(frame + 16, win, WIN);

		uint8_t restamp[REAC_CTRL_BLOCK_LEN];
		memcpy(restamp, win + 2, sizeof restamp);
		reac_ctrl_block_cksum_stamp(restamp);

		int rec_ok = -1;
		if (win[2] == 0x04 && win[3] == 0x03 && win[10] == win[5] - 5 &&
		    win[11] == 0xf0 && win[12] == 0x41) {
			int record_len = win[5] - 0x0d;
			if (record_len > 0 && 18 + record_len <= WIN)
				rec_ok = reac_ctrl_record_cksum_verify(win + 18,
				                                       (size_t)record_len);
		}
		printf("{\"block_ok\":%d,\"block_cksum\":%d,\"restamped\":%d,"
		       "\"record_ok\":%d}\n",
		       reac_ctrl_checksum_verify(frame) == 0,
		       win[WIN - 1], restamp[REAC_CTRL_BLOCK_LEN - 1],
		       rec_ok);
	}
	return 0;
}

int main(int argc, char **argv)
{
	if (argc >= 3 && !strcmp(argv[1], "scene"))
		return cmd_scene(argv[2]);
	if (argc >= 3 && !strcmp(argv[1], "scene-build"))
		return cmd_scene_build(argv[2]);
	if (argc >= 5 && (!strcmp(argv[1], "headamp") ||
	                  !strcmp(argv[1], "headamp-badorder"))) {
		uint8_t win[WIN];
		build_headamp(win, atoi(argv[2]), atoi(argv[3]), atoi(argv[4]),
		              !strcmp(argv[1], "headamp"));
		put_hex(win, WIN);
		return 0;
	}
	if (argc >= 2 && !strcmp(argv[1], "verify"))
		return cmd_verify();

	fprintf(stderr,
	        "usage: %s scene BODY | scene-build MAC | headamp CH P V |\n"
	        "       %s headamp-badorder CH P V | verify < hexlines\n",
	        argv[0], argv[0]);
	return 2;
}
