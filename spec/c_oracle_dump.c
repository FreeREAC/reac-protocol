// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
//
// c_oracle_dump — the COMPILED libreac oracle, rendered as JSON so the spec's
// generated parser can be diffed against it field for field.
//
// spec/reac_xcheck.py is hermetic on purpose: it compares reac.ksy against the
// truth tables the C tests are held to, plus Python transcriptions of the C
// contracts. That catches spec drift, but a transcription is not the compiler's
// output — it is a second reading of the same header, and a reading can be
// wrong in the same direction twice. This program removes that step: it links
// the real libreac and prints what reac_frame_clean_len(),
// reac_upstream_channels(), reac_upstream_decode(), reac_decode() and
// reac_downstream_build() actually return.
//
// It is DEV-ONLY tooling. It is not built by `make check`, not shipped, and not
// in CI's hermetic gate — it needs a libreac checkout and a C compiler that the
// spec repo otherwise does not depend on. See `make check-oracle`.
//
// Needs libreac >= 0.5.0: it calls reac_decode_plain_le(), which is where the
// refuted plain-LE reading went when reac_decode() was fixed to un-braid.
//
//   c_oracle_dump upstream  < hexlines   one hex frame per line -> one JSON object per line
//   c_oracle_dump downstream             synthesize a 40-ch downstream frame and dump
//                                        what libreac decodes it to, plus the plain-LE
//                                        diagnostic reading of the same bytes

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <reac/reac.h>
#include <reac/reac_decode.h>
#include <reac/reac_upstream.h>
#include <reac/reac_encode.h>
#include <reac/reac_braid.h>

#define MAXFRAME 4096

static int hexval(int c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

/* hex string -> bytes; returns length, or -1 on a malformed line */
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

/* planar s24 LE triple -> signed int */
static int32_t s24(const uint8_t *p)
{
	int32_t v = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16));
	return (v & 0x00800000) ? (v | ~0x00FFFFFF) : v;
}

static void print_planar(const uint8_t *pcm, int nch, int ns)
{
	printf("[");
	for (int ch = 0; ch < nch; ch++) {
		printf("%s[", ch ? "," : "");
		for (int s = 0; s < ns; s++)
			printf("%s%d", s ? "," : "", s24(pcm + ((size_t)ch * ns + s) * 3));
		printf("]");
	}
	printf("]");
}

static int do_upstream(void)
{
	char line[MAXFRAME * 2 + 8];
	uint8_t frame[MAXFRAME];
	uint8_t pcm[REAC_MAX_CHANNELS * REAC_SAMPLES_PER_PKT * 3];

	while (fgets(line, sizeof line, stdin)) {
		if (line[0] == '\n' || line[0] == '\r' || line[0] == '\0')
			continue;
		int len = unhex(line, frame, sizeof frame);
		if (len < 0) {
			fprintf(stderr, "c_oracle_dump: malformed hex line\n");
			return 2;
		}
		int nch = reac_upstream_channels((size_t)len);
		printf("{\"raw_len\":%d", len);
		printf(",\"is_reac\":%d", reac_frame_is_reac(frame, (size_t)len));
		printf(",\"clean_len\":%zu", reac_frame_clean_len((size_t)len));
		printf(",\"upstream_channels\":%d", nch);
		printf(",\"counter\":%u", (unsigned)reac_frame_counter(frame));
		if (nch > 0) {
			int ns = reac_upstream_decode(frame, (size_t)len, pcm);
			printf(",\"upstream_samples\":%d", ns);
			if (ns > 0) {
				printf(",\"upstream_pcm\":");
				print_planar(pcm, nch, ns);
			}
		}
		printf("}\n");
	}
	return 0;
}

/* A deterministic, exactly-representable test signal: the target s24 value is
 * chosen first and divided by 2^23, so float carries it losslessly (24-bit
 * mantissa) and reac_f32_to_s24le() must reproduce the integer exactly. Any
 * mismatch downstream is therefore a LAYOUT difference, never rounding. */
static int32_t want(int ch, int s)
{
	int32_t v = (int32_t)(((uint32_t)ch * 7919u + (uint32_t)s * 104729u) & 0x00FFFFFFu);
	return v - 0x00800000;
}

static int do_downstream(void)
{
	static float plane[REAC_MAX_CHANNELS][REAC_SAMPLES_PER_PKT];
	float *planar[REAC_MAX_CHANNELS];
	uint8_t frame[REAC_FRAME_BYTES];
	uint8_t pcm[REAC_MAX_CHANNELS * REAC_SAMPLES_PER_PKT * 3];
	const uint8_t src[6] = { 0x00, 0x40, 0xab, 0x00, 0x00, 0x01 };

	for (int ch = 0; ch < REAC_MAX_CHANNELS; ch++) {
		planar[ch] = plane[ch];
		for (int s = 0; s < REAC_SAMPLES_PER_PKT; s++)
			plane[ch][s] = (float)want(ch, s) / 8388608.0f;
	}

	int len = reac_downstream_build(frame, planar, REAC_MAX_CHANNELS,
	                                REAC_SAMPLES_PER_PKT, 0x1234, src);

	printf("{\"built_len\":%d", len);
	printf(",\"hex\":\"");
	for (int i = 0; i < len; i++)
		printf("%02x", frame[i]);
	printf("\"");
	printf(",\"clean_len\":%zu", reac_frame_clean_len((size_t)len));
	printf(",\"upstream_channels\":%d", reac_upstream_channels((size_t)len));
	printf(",\"counter\":%u", (unsigned)reac_frame_counter(frame));

	/* what was asked for */
	printf(",\"encoded_pcm\":[");
	for (int ch = 0; ch < REAC_MAX_CHANNELS; ch++) {
		printf("%s[", ch ? "," : "");
		for (int s = 0; s < REAC_SAMPLES_PER_PKT; s++)
			printf("%s%d", s ? "," : "", want(ch, s));
		printf("]");
	}
	printf("]");

	/* The braid, read straight off the layout oracle. There is no exported
	 * braid DECODER for the downstream width: reac_upstream_decode() rejects 40
	 * channels by contract (that width is the master broadcast, never a box
	 * return). So the braid reading goes through reac_braid_pos() — the same
	 * inline the encoder used — rather than through a guard that would refuse
	 * the frame. */
	printf(",\"braid_samples\":%d", REAC_SAMPLES_PER_PKT);
	printf(",\"braid_pcm\":[");
	for (int ch = 0; ch < REAC_MAX_CHANNELS; ch++) {
		printf("%s[", ch ? "," : "");
		for (int s = 0; s < REAC_SAMPLES_PER_PKT; s++) {
			size_t pos[3];
			uint8_t t[3];
			reac_braid_pos(s, ch, REAC_MAX_CHANNELS, pos);
			t[0] = frame[REAC_AUDIO_OFFSET + pos[0]];
			t[1] = frame[REAC_AUDIO_OFFSET + pos[1]];
			t[2] = frame[REAC_AUDIO_OFFSET + pos[2]];
			printf("%s%d", s ? "," : "", s24(t));
		}
		printf("]");
	}
	printf("]");

	/* The shipped decoder. Since libreac 0.5.0 this un-braids, so it must agree
	 * with braid_pcm above and with encoded_pcm — the library reads back what it
	 * writes. Before 0.5.0 it read plain LE and agreed with neither. */
	int ns = reac_decode(frame, (size_t)len, reac_mode_for(48000), pcm);
	printf(",\"decode_samples\":%d", ns);
	if (ns > 0) {
		printf(",\"decode_pcm\":");
		print_planar(pcm, REAC_MAX_CHANNELS, ns);
	}

	/* The refuted plain-LE reading, kept in libreac as a named diagnostic. Dumped
	 * so the spec can show it is a DIFFERENT reading of the same bytes rather
	 * than asserting the point in prose. */
	ns = reac_decode_plain_le(frame, (size_t)len, reac_mode_for(48000), pcm);
	printf(",\"plain_le_samples\":%d", ns);
	if (ns > 0) {
		printf(",\"plain_le_pcm\":");
		print_planar(pcm, REAC_MAX_CHANNELS, ns);
	}
	printf("}\n");
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 2 && !strcmp(argv[1], "upstream"))
		return do_upstream();
	if (argc == 2 && !strcmp(argv[1], "downstream"))
		return do_downstream();
	fprintf(stderr, "usage: %s upstream < hexlines\n       %s downstream\n",
	        argv[0], argv[0]);
	return 2;
}
