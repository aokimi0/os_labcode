
bin/kernel:     file format elf64-littleriscv


Disassembly of section .text:

0000000080200000 <kern_entry>:
    .section .text,"ax",%progbits
    .globl kern_entry
kern_entry:
    la sp, bootstacktop
    80200000:	00003117          	auipc	sp,0x3
    80200004:	00010113          	mv	sp,sp
    tail kern_init
    80200008:	a009                	j	8020000a <kern_init>

000000008020000a <kern_init>:
#include <sbi.h>
int kern_init(void) __attribute__((noreturn));

int kern_init(void) {
    extern char edata[], end[];
    memset(edata, 0, end - edata);
    8020000a:	00003517          	auipc	a0,0x3
    8020000e:	ffe50513          	addi	a0,a0,-2 # 80203008 <edata>
    80200012:	00003617          	auipc	a2,0x3
    80200016:	ff660613          	addi	a2,a2,-10 # 80203008 <edata>
int kern_init(void) {
    8020001a:	1141                	addi	sp,sp,-16 # 80202ff0 <bootstack+0x1ff0>
    memset(edata, 0, end - edata);
    8020001c:	4581                	li	a1,0
    8020001e:	8e09                	sub	a2,a2,a0
int kern_init(void) {
    80200020:	e406                	sd	ra,8(sp)
    memset(edata, 0, end - edata);
    80200022:	492000ef          	jal	802004b4 <memset>

    const char *message = "(THU.CST) os is loading ...\n";
    cprintf("%s\n\n", message);
    80200026:	00000597          	auipc	a1,0x0
    8020002a:	4a258593          	addi	a1,a1,1186 # 802004c8 <memset+0x14>
    8020002e:	00000517          	auipc	a0,0x0
    80200032:	4ba50513          	addi	a0,a0,1210 # 802004e8 <memset+0x34>
    80200036:	020000ef          	jal	80200056 <cprintf>
    while (1)
    8020003a:	a001                	j	8020003a <kern_init+0x30>

000000008020003c <cputch>:

/* *
 * cputch - writes a single character @c to stdout, and it will
 * increace the value of counter pointed by @cnt.
 * */
static void cputch(int c, int *cnt) {
    8020003c:	1141                	addi	sp,sp,-16
    8020003e:	e022                	sd	s0,0(sp)
    80200040:	e406                	sd	ra,8(sp)
    80200042:	842e                	mv	s0,a1
    cons_putc(c);
    80200044:	046000ef          	jal	8020008a <cons_putc>
    (*cnt)++;
    80200048:	401c                	lw	a5,0(s0)
}
    8020004a:	60a2                	ld	ra,8(sp)
    (*cnt)++;
    8020004c:	2785                	addiw	a5,a5,1
    8020004e:	c01c                	sw	a5,0(s0)
}
    80200050:	6402                	ld	s0,0(sp)
    80200052:	0141                	addi	sp,sp,16
    80200054:	8082                	ret

0000000080200056 <cprintf>:
 * cprintf - formats a string and writes it to stdout
 *
 * The return value is the number of characters which would be
 * written to stdout.
 * */
int cprintf(const char *fmt, ...) {
    80200056:	711d                	addi	sp,sp,-96
    va_list ap;
    int cnt;
    va_start(ap, fmt);
    80200058:	02810313          	addi	t1,sp,40
int cprintf(const char *fmt, ...) {
    8020005c:	f42e                	sd	a1,40(sp)
    8020005e:	f832                	sd	a2,48(sp)
    80200060:	fc36                	sd	a3,56(sp)
    vprintfmt((void *)cputch, &cnt, fmt, ap);
    80200062:	862a                	mv	a2,a0
    80200064:	004c                	addi	a1,sp,4
    80200066:	00000517          	auipc	a0,0x0
    8020006a:	fd650513          	addi	a0,a0,-42 # 8020003c <cputch>
    8020006e:	869a                	mv	a3,t1
int cprintf(const char *fmt, ...) {
    80200070:	ec06                	sd	ra,24(sp)
    80200072:	e0ba                	sd	a4,64(sp)
    80200074:	e4be                	sd	a5,72(sp)
    80200076:	e8c2                	sd	a6,80(sp)
    80200078:	ecc6                	sd	a7,88(sp)
    va_start(ap, fmt);
    8020007a:	e41a                	sd	t1,8(sp)
    int cnt = 0;
    8020007c:	c202                	sw	zero,4(sp)
    vprintfmt((void *)cputch, &cnt, fmt, ap);
    8020007e:	07e000ef          	jal	802000fc <vprintfmt>
    cnt = vcprintf(fmt, ap);
    va_end(ap);
    return cnt;
}
    80200082:	60e2                	ld	ra,24(sp)
    80200084:	4512                	lw	a0,4(sp)
    80200086:	6125                	addi	sp,sp,96
    80200088:	8082                	ret

000000008020008a <cons_putc>:
    8020008a:	0ff57513          	zext.b	a0,a0
    8020008e:	aec5                	j	8020047e <sbi_console_putchar>

0000000080200090 <printnum>:
    80200090:	02069813          	slli	a6,a3,0x20
    80200094:	7179                	addi	sp,sp,-48
    80200096:	02085813          	srli	a6,a6,0x20
    8020009a:	e052                	sd	s4,0(sp)
    8020009c:	03067a33          	remu	s4,a2,a6
    802000a0:	f022                	sd	s0,32(sp)
    802000a2:	ec26                	sd	s1,24(sp)
    802000a4:	e84a                	sd	s2,16(sp)
    802000a6:	f406                	sd	ra,40(sp)
    802000a8:	e44e                	sd	s3,8(sp)
    802000aa:	84aa                	mv	s1,a0
    802000ac:	892e                	mv	s2,a1
    802000ae:	fff7041b          	addiw	s0,a4,-1
    802000b2:	2a01                	sext.w	s4,s4
    802000b4:	03067e63          	bgeu	a2,a6,802000f0 <printnum+0x60>
    802000b8:	89be                	mv	s3,a5
    802000ba:	00805763          	blez	s0,802000c8 <printnum+0x38>
    802000be:	347d                	addiw	s0,s0,-1
    802000c0:	85ca                	mv	a1,s2
    802000c2:	854e                	mv	a0,s3
    802000c4:	9482                	jalr	s1
    802000c6:	fc65                	bnez	s0,802000be <printnum+0x2e>
    802000c8:	1a02                	slli	s4,s4,0x20
    802000ca:	00000797          	auipc	a5,0x0
    802000ce:	42678793          	addi	a5,a5,1062 # 802004f0 <memset+0x3c>
    802000d2:	020a5a13          	srli	s4,s4,0x20
    802000d6:	9a3e                	add	s4,s4,a5
    802000d8:	7402                	ld	s0,32(sp)
    802000da:	000a4503          	lbu	a0,0(s4)
    802000de:	70a2                	ld	ra,40(sp)
    802000e0:	69a2                	ld	s3,8(sp)
    802000e2:	6a02                	ld	s4,0(sp)
    802000e4:	85ca                	mv	a1,s2
    802000e6:	87a6                	mv	a5,s1
    802000e8:	6942                	ld	s2,16(sp)
    802000ea:	64e2                	ld	s1,24(sp)
    802000ec:	6145                	addi	sp,sp,48
    802000ee:	8782                	jr	a5
    802000f0:	03065633          	divu	a2,a2,a6
    802000f4:	8722                	mv	a4,s0
    802000f6:	f9bff0ef          	jal	80200090 <printnum>
    802000fa:	b7f9                	j	802000c8 <printnum+0x38>

00000000802000fc <vprintfmt>:
    802000fc:	7119                	addi	sp,sp,-128
    802000fe:	f4a6                	sd	s1,104(sp)
    80200100:	f0ca                	sd	s2,96(sp)
    80200102:	ecce                	sd	s3,88(sp)
    80200104:	e8d2                	sd	s4,80(sp)
    80200106:	e4d6                	sd	s5,72(sp)
    80200108:	e0da                	sd	s6,64(sp)
    8020010a:	fc5e                	sd	s7,56(sp)
    8020010c:	f06a                	sd	s10,32(sp)
    8020010e:	fc86                	sd	ra,120(sp)
    80200110:	f8a2                	sd	s0,112(sp)
    80200112:	f862                	sd	s8,48(sp)
    80200114:	f466                	sd	s9,40(sp)
    80200116:	ec6e                	sd	s11,24(sp)
    80200118:	892a                	mv	s2,a0
    8020011a:	84ae                	mv	s1,a1
    8020011c:	8d32                	mv	s10,a2
    8020011e:	8a36                	mv	s4,a3
    80200120:	02500993          	li	s3,37
    80200124:	5b7d                	li	s6,-1
    80200126:	00000a97          	auipc	s5,0x0
    8020012a:	47ea8a93          	addi	s5,s5,1150 # 802005a4 <memset+0xf0>
    8020012e:	00000b97          	auipc	s7,0x0
    80200132:	5d2b8b93          	addi	s7,s7,1490 # 80200700 <error_string>
    80200136:	000d4503          	lbu	a0,0(s10)
    8020013a:	001d0413          	addi	s0,s10,1
    8020013e:	01350a63          	beq	a0,s3,80200152 <vprintfmt+0x56>
    80200142:	c121                	beqz	a0,80200182 <vprintfmt+0x86>
    80200144:	85a6                	mv	a1,s1
    80200146:	0405                	addi	s0,s0,1
    80200148:	9902                	jalr	s2
    8020014a:	fff44503          	lbu	a0,-1(s0)
    8020014e:	ff351ae3          	bne	a0,s3,80200142 <vprintfmt+0x46>
    80200152:	00044603          	lbu	a2,0(s0)
    80200156:	02000793          	li	a5,32
    8020015a:	4c81                	li	s9,0
    8020015c:	4881                	li	a7,0
    8020015e:	5c7d                	li	s8,-1
    80200160:	5dfd                	li	s11,-1
    80200162:	05500513          	li	a0,85
    80200166:	4825                	li	a6,9
    80200168:	fdd6059b          	addiw	a1,a2,-35
    8020016c:	0ff5f593          	zext.b	a1,a1
    80200170:	00140d13          	addi	s10,s0,1
    80200174:	04b56263          	bltu	a0,a1,802001b8 <vprintfmt+0xbc>
    80200178:	058a                	slli	a1,a1,0x2
    8020017a:	95d6                	add	a1,a1,s5
    8020017c:	4194                	lw	a3,0(a1)
    8020017e:	96d6                	add	a3,a3,s5
    80200180:	8682                	jr	a3
    80200182:	70e6                	ld	ra,120(sp)
    80200184:	7446                	ld	s0,112(sp)
    80200186:	74a6                	ld	s1,104(sp)
    80200188:	7906                	ld	s2,96(sp)
    8020018a:	69e6                	ld	s3,88(sp)
    8020018c:	6a46                	ld	s4,80(sp)
    8020018e:	6aa6                	ld	s5,72(sp)
    80200190:	6b06                	ld	s6,64(sp)
    80200192:	7be2                	ld	s7,56(sp)
    80200194:	7c42                	ld	s8,48(sp)
    80200196:	7ca2                	ld	s9,40(sp)
    80200198:	7d02                	ld	s10,32(sp)
    8020019a:	6de2                	ld	s11,24(sp)
    8020019c:	6109                	addi	sp,sp,128
    8020019e:	8082                	ret
    802001a0:	87b2                	mv	a5,a2
    802001a2:	00144603          	lbu	a2,1(s0)
    802001a6:	846a                	mv	s0,s10
    802001a8:	00140d13          	addi	s10,s0,1
    802001ac:	fdd6059b          	addiw	a1,a2,-35
    802001b0:	0ff5f593          	zext.b	a1,a1
    802001b4:	fcb572e3          	bgeu	a0,a1,80200178 <vprintfmt+0x7c>
    802001b8:	85a6                	mv	a1,s1
    802001ba:	02500513          	li	a0,37
    802001be:	9902                	jalr	s2
    802001c0:	fff44783          	lbu	a5,-1(s0)
    802001c4:	8d22                	mv	s10,s0
    802001c6:	f73788e3          	beq	a5,s3,80200136 <vprintfmt+0x3a>
    802001ca:	ffed4783          	lbu	a5,-2(s10)
    802001ce:	1d7d                	addi	s10,s10,-1
    802001d0:	ff379de3          	bne	a5,s3,802001ca <vprintfmt+0xce>
    802001d4:	b78d                	j	80200136 <vprintfmt+0x3a>
    802001d6:	fd060c1b          	addiw	s8,a2,-48
    802001da:	00144603          	lbu	a2,1(s0)
    802001de:	846a                	mv	s0,s10
    802001e0:	fd06069b          	addiw	a3,a2,-48
    802001e4:	0006059b          	sext.w	a1,a2
    802001e8:	02d86463          	bltu	a6,a3,80200210 <vprintfmt+0x114>
    802001ec:	00144603          	lbu	a2,1(s0)
    802001f0:	002c169b          	slliw	a3,s8,0x2
    802001f4:	0186873b          	addw	a4,a3,s8
    802001f8:	0017171b          	slliw	a4,a4,0x1
    802001fc:	9f2d                	addw	a4,a4,a1
    802001fe:	fd06069b          	addiw	a3,a2,-48
    80200202:	0405                	addi	s0,s0,1
    80200204:	fd070c1b          	addiw	s8,a4,-48
    80200208:	0006059b          	sext.w	a1,a2
    8020020c:	fed870e3          	bgeu	a6,a3,802001ec <vprintfmt+0xf0>
    80200210:	f40ddce3          	bgez	s11,80200168 <vprintfmt+0x6c>
    80200214:	8de2                	mv	s11,s8
    80200216:	5c7d                	li	s8,-1
    80200218:	bf81                	j	80200168 <vprintfmt+0x6c>
    8020021a:	fffdc693          	not	a3,s11
    8020021e:	96fd                	srai	a3,a3,0x3f
    80200220:	00ddfdb3          	and	s11,s11,a3
    80200224:	00144603          	lbu	a2,1(s0)
    80200228:	2d81                	sext.w	s11,s11
    8020022a:	846a                	mv	s0,s10
    8020022c:	bf35                	j	80200168 <vprintfmt+0x6c>
    8020022e:	000a2c03          	lw	s8,0(s4)
    80200232:	00144603          	lbu	a2,1(s0)
    80200236:	0a21                	addi	s4,s4,8
    80200238:	846a                	mv	s0,s10
    8020023a:	bfd9                	j	80200210 <vprintfmt+0x114>
    8020023c:	4705                	li	a4,1
    8020023e:	008a0593          	addi	a1,s4,8
    80200242:	01174463          	blt	a4,a7,8020024a <vprintfmt+0x14e>
    80200246:	1a088e63          	beqz	a7,80200402 <vprintfmt+0x306>
    8020024a:	000a3603          	ld	a2,0(s4)
    8020024e:	46c1                	li	a3,16
    80200250:	8a2e                	mv	s4,a1
    80200252:	2781                	sext.w	a5,a5
    80200254:	876e                	mv	a4,s11
    80200256:	85a6                	mv	a1,s1
    80200258:	854a                	mv	a0,s2
    8020025a:	e37ff0ef          	jal	80200090 <printnum>
    8020025e:	bde1                	j	80200136 <vprintfmt+0x3a>
    80200260:	000a2503          	lw	a0,0(s4)
    80200264:	85a6                	mv	a1,s1
    80200266:	0a21                	addi	s4,s4,8
    80200268:	9902                	jalr	s2
    8020026a:	b5f1                	j	80200136 <vprintfmt+0x3a>
    8020026c:	4705                	li	a4,1
    8020026e:	008a0593          	addi	a1,s4,8
    80200272:	01174463          	blt	a4,a7,8020027a <vprintfmt+0x17e>
    80200276:	18088163          	beqz	a7,802003f8 <vprintfmt+0x2fc>
    8020027a:	000a3603          	ld	a2,0(s4)
    8020027e:	46a9                	li	a3,10
    80200280:	8a2e                	mv	s4,a1
    80200282:	bfc1                	j	80200252 <vprintfmt+0x156>
    80200284:	00144603          	lbu	a2,1(s0)
    80200288:	4c85                	li	s9,1
    8020028a:	846a                	mv	s0,s10
    8020028c:	bdf1                	j	80200168 <vprintfmt+0x6c>
    8020028e:	85a6                	mv	a1,s1
    80200290:	02500513          	li	a0,37
    80200294:	9902                	jalr	s2
    80200296:	b545                	j	80200136 <vprintfmt+0x3a>
    80200298:	00144603          	lbu	a2,1(s0)
    8020029c:	2885                	addiw	a7,a7,1
    8020029e:	846a                	mv	s0,s10
    802002a0:	b5e1                	j	80200168 <vprintfmt+0x6c>
    802002a2:	4705                	li	a4,1
    802002a4:	008a0593          	addi	a1,s4,8
    802002a8:	01174463          	blt	a4,a7,802002b0 <vprintfmt+0x1b4>
    802002ac:	14088163          	beqz	a7,802003ee <vprintfmt+0x2f2>
    802002b0:	000a3603          	ld	a2,0(s4)
    802002b4:	46a1                	li	a3,8
    802002b6:	8a2e                	mv	s4,a1
    802002b8:	bf69                	j	80200252 <vprintfmt+0x156>
    802002ba:	03000513          	li	a0,48
    802002be:	85a6                	mv	a1,s1
    802002c0:	e03e                	sd	a5,0(sp)
    802002c2:	9902                	jalr	s2
    802002c4:	85a6                	mv	a1,s1
    802002c6:	07800513          	li	a0,120
    802002ca:	9902                	jalr	s2
    802002cc:	0a21                	addi	s4,s4,8
    802002ce:	6782                	ld	a5,0(sp)
    802002d0:	46c1                	li	a3,16
    802002d2:	ff8a3603          	ld	a2,-8(s4)
    802002d6:	bfb5                	j	80200252 <vprintfmt+0x156>
    802002d8:	000a3403          	ld	s0,0(s4)
    802002dc:	008a0713          	addi	a4,s4,8
    802002e0:	e03a                	sd	a4,0(sp)
    802002e2:	14040263          	beqz	s0,80200426 <vprintfmt+0x32a>
    802002e6:	0fb05763          	blez	s11,802003d4 <vprintfmt+0x2d8>
    802002ea:	02d00693          	li	a3,45
    802002ee:	0cd79163          	bne	a5,a3,802003b0 <vprintfmt+0x2b4>
    802002f2:	00044783          	lbu	a5,0(s0)
    802002f6:	0007851b          	sext.w	a0,a5
    802002fa:	cf85                	beqz	a5,80200332 <vprintfmt+0x236>
    802002fc:	00140a13          	addi	s4,s0,1
    80200300:	05e00413          	li	s0,94
    80200304:	000c4563          	bltz	s8,8020030e <vprintfmt+0x212>
    80200308:	3c7d                	addiw	s8,s8,-1
    8020030a:	036c0263          	beq	s8,s6,8020032e <vprintfmt+0x232>
    8020030e:	85a6                	mv	a1,s1
    80200310:	0e0c8e63          	beqz	s9,8020040c <vprintfmt+0x310>
    80200314:	3781                	addiw	a5,a5,-32
    80200316:	0ef47b63          	bgeu	s0,a5,8020040c <vprintfmt+0x310>
    8020031a:	03f00513          	li	a0,63
    8020031e:	9902                	jalr	s2
    80200320:	000a4783          	lbu	a5,0(s4)
    80200324:	3dfd                	addiw	s11,s11,-1
    80200326:	0a05                	addi	s4,s4,1
    80200328:	0007851b          	sext.w	a0,a5
    8020032c:	ffe1                	bnez	a5,80200304 <vprintfmt+0x208>
    8020032e:	01b05963          	blez	s11,80200340 <vprintfmt+0x244>
    80200332:	3dfd                	addiw	s11,s11,-1
    80200334:	85a6                	mv	a1,s1
    80200336:	02000513          	li	a0,32
    8020033a:	9902                	jalr	s2
    8020033c:	fe0d9be3          	bnez	s11,80200332 <vprintfmt+0x236>
    80200340:	6a02                	ld	s4,0(sp)
    80200342:	bbd5                	j	80200136 <vprintfmt+0x3a>
    80200344:	4705                	li	a4,1
    80200346:	008a0c93          	addi	s9,s4,8
    8020034a:	01174463          	blt	a4,a7,80200352 <vprintfmt+0x256>
    8020034e:	08088d63          	beqz	a7,802003e8 <vprintfmt+0x2ec>
    80200352:	000a3403          	ld	s0,0(s4)
    80200356:	0a044d63          	bltz	s0,80200410 <vprintfmt+0x314>
    8020035a:	8622                	mv	a2,s0
    8020035c:	8a66                	mv	s4,s9
    8020035e:	46a9                	li	a3,10
    80200360:	bdcd                	j	80200252 <vprintfmt+0x156>
    80200362:	000a2783          	lw	a5,0(s4)
    80200366:	4719                	li	a4,6
    80200368:	0a21                	addi	s4,s4,8
    8020036a:	41f7d69b          	sraiw	a3,a5,0x1f
    8020036e:	8fb5                	xor	a5,a5,a3
    80200370:	40d786bb          	subw	a3,a5,a3
    80200374:	02d74163          	blt	a4,a3,80200396 <vprintfmt+0x29a>
    80200378:	00369793          	slli	a5,a3,0x3
    8020037c:	97de                	add	a5,a5,s7
    8020037e:	639c                	ld	a5,0(a5)
    80200380:	cb99                	beqz	a5,80200396 <vprintfmt+0x29a>
    80200382:	86be                	mv	a3,a5
    80200384:	00000617          	auipc	a2,0x0
    80200388:	19c60613          	addi	a2,a2,412 # 80200520 <memset+0x6c>
    8020038c:	85a6                	mv	a1,s1
    8020038e:	854a                	mv	a0,s2
    80200390:	0ce000ef          	jal	8020045e <printfmt>
    80200394:	b34d                	j	80200136 <vprintfmt+0x3a>
    80200396:	00000617          	auipc	a2,0x0
    8020039a:	17a60613          	addi	a2,a2,378 # 80200510 <memset+0x5c>
    8020039e:	85a6                	mv	a1,s1
    802003a0:	854a                	mv	a0,s2
    802003a2:	0bc000ef          	jal	8020045e <printfmt>
    802003a6:	bb41                	j	80200136 <vprintfmt+0x3a>
    802003a8:	00000417          	auipc	s0,0x0
    802003ac:	16040413          	addi	s0,s0,352 # 80200508 <memset+0x54>
    802003b0:	85e2                	mv	a1,s8
    802003b2:	8522                	mv	a0,s0
    802003b4:	e43e                	sd	a5,8(sp)
    802003b6:	0e2000ef          	jal	80200498 <strnlen>
    802003ba:	40ad8dbb          	subw	s11,s11,a0
    802003be:	01b05b63          	blez	s11,802003d4 <vprintfmt+0x2d8>
    802003c2:	67a2                	ld	a5,8(sp)
    802003c4:	00078a1b          	sext.w	s4,a5
    802003c8:	3dfd                	addiw	s11,s11,-1
    802003ca:	85a6                	mv	a1,s1
    802003cc:	8552                	mv	a0,s4
    802003ce:	9902                	jalr	s2
    802003d0:	fe0d9ce3          	bnez	s11,802003c8 <vprintfmt+0x2cc>
    802003d4:	00044783          	lbu	a5,0(s0)
    802003d8:	00140a13          	addi	s4,s0,1
    802003dc:	0007851b          	sext.w	a0,a5
    802003e0:	d3a5                	beqz	a5,80200340 <vprintfmt+0x244>
    802003e2:	05e00413          	li	s0,94
    802003e6:	bf39                	j	80200304 <vprintfmt+0x208>
    802003e8:	000a2403          	lw	s0,0(s4)
    802003ec:	b7ad                	j	80200356 <vprintfmt+0x25a>
    802003ee:	000a6603          	lwu	a2,0(s4)
    802003f2:	46a1                	li	a3,8
    802003f4:	8a2e                	mv	s4,a1
    802003f6:	bdb1                	j	80200252 <vprintfmt+0x156>
    802003f8:	000a6603          	lwu	a2,0(s4)
    802003fc:	46a9                	li	a3,10
    802003fe:	8a2e                	mv	s4,a1
    80200400:	bd89                	j	80200252 <vprintfmt+0x156>
    80200402:	000a6603          	lwu	a2,0(s4)
    80200406:	46c1                	li	a3,16
    80200408:	8a2e                	mv	s4,a1
    8020040a:	b5a1                	j	80200252 <vprintfmt+0x156>
    8020040c:	9902                	jalr	s2
    8020040e:	bf09                	j	80200320 <vprintfmt+0x224>
    80200410:	85a6                	mv	a1,s1
    80200412:	02d00513          	li	a0,45
    80200416:	e03e                	sd	a5,0(sp)
    80200418:	9902                	jalr	s2
    8020041a:	6782                	ld	a5,0(sp)
    8020041c:	8a66                	mv	s4,s9
    8020041e:	40800633          	neg	a2,s0
    80200422:	46a9                	li	a3,10
    80200424:	b53d                	j	80200252 <vprintfmt+0x156>
    80200426:	03b05163          	blez	s11,80200448 <vprintfmt+0x34c>
    8020042a:	02d00693          	li	a3,45
    8020042e:	f6d79de3          	bne	a5,a3,802003a8 <vprintfmt+0x2ac>
    80200432:	00000417          	auipc	s0,0x0
    80200436:	0d640413          	addi	s0,s0,214 # 80200508 <memset+0x54>
    8020043a:	02800793          	li	a5,40
    8020043e:	02800513          	li	a0,40
    80200442:	00140a13          	addi	s4,s0,1
    80200446:	bd6d                	j	80200300 <vprintfmt+0x204>
    80200448:	00000a17          	auipc	s4,0x0
    8020044c:	0c1a0a13          	addi	s4,s4,193 # 80200509 <memset+0x55>
    80200450:	02800513          	li	a0,40
    80200454:	02800793          	li	a5,40
    80200458:	05e00413          	li	s0,94
    8020045c:	b565                	j	80200304 <vprintfmt+0x208>

000000008020045e <printfmt>:
    8020045e:	715d                	addi	sp,sp,-80
    80200460:	02810313          	addi	t1,sp,40
    80200464:	f436                	sd	a3,40(sp)
    80200466:	869a                	mv	a3,t1
    80200468:	ec06                	sd	ra,24(sp)
    8020046a:	f83a                	sd	a4,48(sp)
    8020046c:	fc3e                	sd	a5,56(sp)
    8020046e:	e0c2                	sd	a6,64(sp)
    80200470:	e4c6                	sd	a7,72(sp)
    80200472:	e41a                	sd	t1,8(sp)
    80200474:	c89ff0ef          	jal	802000fc <vprintfmt>
    80200478:	60e2                	ld	ra,24(sp)
    8020047a:	6161                	addi	sp,sp,80
    8020047c:	8082                	ret

000000008020047e <sbi_console_putchar>:
    8020047e:	4781                	li	a5,0
    80200480:	00003717          	auipc	a4,0x3
    80200484:	b8073703          	ld	a4,-1152(a4) # 80203000 <SBI_CONSOLE_PUTCHAR>
    80200488:	88ba                	mv	a7,a4
    8020048a:	852a                	mv	a0,a0
    8020048c:	85be                	mv	a1,a5
    8020048e:	863e                	mv	a2,a5
    80200490:	00000073          	ecall
    80200494:	87aa                	mv	a5,a0
    80200496:	8082                	ret

0000000080200498 <strnlen>:
    80200498:	4781                	li	a5,0
    8020049a:	e589                	bnez	a1,802004a4 <strnlen+0xc>
    8020049c:	a811                	j	802004b0 <strnlen+0x18>
    8020049e:	0785                	addi	a5,a5,1
    802004a0:	00f58863          	beq	a1,a5,802004b0 <strnlen+0x18>
    802004a4:	00f50733          	add	a4,a0,a5
    802004a8:	00074703          	lbu	a4,0(a4)
    802004ac:	fb6d                	bnez	a4,8020049e <strnlen+0x6>
    802004ae:	85be                	mv	a1,a5
    802004b0:	852e                	mv	a0,a1
    802004b2:	8082                	ret

00000000802004b4 <memset>:
    802004b4:	ca01                	beqz	a2,802004c4 <memset+0x10>
    802004b6:	962a                	add	a2,a2,a0
    802004b8:	87aa                	mv	a5,a0
    802004ba:	0785                	addi	a5,a5,1
    802004bc:	feb78fa3          	sb	a1,-1(a5)
    802004c0:	fec79de3          	bne	a5,a2,802004ba <memset+0x6>
    802004c4:	8082                	ret
