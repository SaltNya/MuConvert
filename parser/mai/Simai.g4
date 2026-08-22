/*
 * Simai的ANTLR4语法定义。
 * Simai官方文档：https://w.atwiki.jp/simai/pages/1002.html
 * 本语法同时实现了一些“常见非标准语法”以确保解析的鲁棒性。
 */
grammar Simai;

options { language=CSharp; }

// ---------------------------------------------------------------------------
// 词法
// ---------------------------------------------------------------------------

WS: [ \t\r\n]+ -> channel(HIDDEN);
COMMENT: '||' ~[\r\n]* -> channel(HIDDEN);

COMMA: ',';

TAP_TO_STAR: '$$' | '$';
OVERLAP_MARKER: '@' '{' INT+ '}'; // 可重叠音符流：@{N} 从当前时间起按 1/N 分拍独立推进，不推进主谱时间
WAVE_TIME_SIG: '@' [0-9]+ '/' [0-9]+; // 波形拍号：@分子/分母，仅影响编辑器波形网格，对输出无影响
STAR_TO_TAP: '@';
NO_STAR: '?' | '!';

KEY: [1-8];
TOUCH_AREA: 'A' [1-8] | 'B' [1-8] | 'C' [1-2]? | 'D' [1-8] | 'E' [1-8];

SLIDE_TYPE: '-' | 'v' | '<' | '>' | '^' | 'p' | 'q' | 'pp' | 'qq' | 's' | 'z' | 'w' | 'rp' | 'rq' | 'V' KEY;  // 只有V后面需要多跟一个键位号；rp/rq=反向圆弧（沿pp/qq相反方向绕行）
slideType: SLIDE_TYPE;

INT: [0-9];

int: (KEY | INT)+;
number: int ('.' int)?;

CHART_END: 'E';// 谱面结束那个E

// 时间轴命令：<SV*2> <SV*tap=2,hold=0.75> <HS*1.2> <BOUNCE*8:1> <SPAWN*1.225> 等。
// 内容里允许逗号（分类写法 tap=2,hold=4:1），所以用贪婪的~[<>]*。
COMMAND: '<' [A-Za-z]+ '*' ~[<>]* '>';

MODIFIER: [bmxf]; // m=地雷（AquaMai mod）；语法层不去检查modifier和tap/hold的搭配和合理性，都丢给语义层去搞
modifiers: (MODIFIER | TAP_TO_STAR | STAR_TO_TAP | NO_STAR)*;

// ---------------------------------------------------------------------------
// 语法
// ---------------------------------------------------------------------------

chart: (notations COMMA)* CHART_END? EOF;

// 同一时刻的所有标记，包括note标记、bpm标记、时间轴命令等等
notations: (bpmTag | absulouteStepTag | metTag | commandTag | overlapMarker | waveTimeSig)* noteGroup?;
overlapMarker: OVERLAP_MARKER;
waveTimeSig: WAVE_TIME_SIG;

noteGroup: note eachNote*;
FALSE_EACH: '`'+;
eachNote: sep=('/' | FALSE_EACH) note?;

bpmTag: (lp+='(')+ number (rp+=')')+;
absulouteStepTag: (lp+='{')+ '#' number (rp+='}')+;
metTag: (lp+='{')+ int (rp+='}')+;
commandTag: COMMAND;

note: slide (sharedHeadSlide)* | tap | KEY+ | hold | touch | touchHold; // tap+是因为，simai允许123这种语法、和1/2/3是等价的，但仅限tap之间。

tap: KEY modifiers;

// 出于兼容性（以及simai本身设计的不合理？）考虑，会到处放置很多的modifiers以确保都能解析，解析的时候要把所有的modifiers取并集。
hold: KEY modifiers 'h' modifiers (duration modifiers)?;

touch: TOUCH_AREA modifiers;

touchHold: TOUCH_AREA modifiers 'h' modifiers (duration modifiers)?;

duration: (lp+='[')+ (beats | '#' number) (rp+=']')+;
beats: int ':' int;
    
slideDuration: (lp+='[')+ (
        beats
        | '#' number
        | waitTime '##' asBpm '#' (beats | number)
        | waitTime '##' (beats | number)
        | asBpm '#' (beats | number)
    ) (rp+=']')+;
waitTime: number;
asBpm: number;

// slide的起点和每一段的终点都支持touch区（A1/B1/C/E2/D5等），用于AquaMai mod的NMSSS自定义slide。
slide: (tap | touchHead) slideBody;
touchHead: TOUCH_AREA modifiers;
// * 后跟可选起点键：官方 simai 里 * 后直接跟形状=同头第二条路径（起点=星头键）；*5-3 带起点键=链段续写
// （起点=该键，合法谱面中=上一段终点）。没有 (KEY | TOUCH_AREA)? 时 *5-3 的 5 会被错误恢复吞掉。
sharedHeadSlide: '*' (KEY | TOUCH_AREA)? slideBody;

slideBody // 根据Simai文档规定，分为两种情况。段间允许穿插modifiers（如?无头标记，常见写法如 2^4?rp2[...]）
    : slideType (KEY | TOUCH_AREA) (modifiers slideType (KEY | TOUCH_AREA))* modifiers slideDuration modifiers // 只有最后一段星星有时间指定
    | slideType (KEY | TOUCH_AREA) (modifiers slideDuration slideType (KEY | TOUCH_AREA))* modifiers slideDuration modifiers // 每一段星星都有独立的时间指定
    ;
