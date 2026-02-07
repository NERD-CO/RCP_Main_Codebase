%% Drift-robust UART decode from edge timestamps (no full waveform)
% data.Time in microseconds. data.Time(1) is start; data.Time(2:end) are edges.
% Initial line state is HIGH at t=0.
% UART: 2400 baud, 8N1, idle HIGH, start LOW, stop HIGH, LSB-first
data_path = 'C:\Users\williar9\Downloads\NLX_TTL_Table.csv';
data = readtable(data_path);
%% Build dt segments split by long gaps (no bits yet)
baud_nom = 2400;
Tb_us_nom = 1e6/baud_nom;
bitsPerByte = 10;
byte_us_nom = bitsPerByte * Tb_us_nom;
resetGap_us = 5 * byte_us_nom;
t_us = double(data.Time(:));
t_us = t_us - t_us(1);
edge_us = t_us(2:end);
edge_us = edge_us(edge_us >= 0);
dt_us = diff(edge_us);
% --- NEW: glitch filter (merge implausibly short intervals as noise) ---
dt_us = glitch_merge_dt(dt_us, Tb_us_nom, 0.20);  % 0.20 Tb is a good start
dtSegs = {};
segStart_us = [];
cur = [];
currStart = edge_us(1);

for k = 1:numel(dt_us)
    if dt_us(k) >= resetGap_us
        if ~isempty(cur)
            dtSegs{end+1} = cur; %#ok<AGROW>
            segStart_us(end+1,1) = currStart; %#ok<AGROW>
            cur = [];
        end
        if k+1 <= numel(edge_us)
            currStart = edge_us(k+1);
        end
        continue;
    end
    cur(end+1,1) = dt_us(k); %#ok<AGROW>
end
if ~isempty(cur)
    dtSegs{end+1} = cur;
    segStart_us(end+1,1) = currStart;
end
rows = struct('StartTime_us',{},'StartTime_s',{},'Baud',{},'Score',{},'Type',{},'Line',{},'Bytes',{});
for s = 1:numel(dtSegs)
    dtSeg = dtSegs{s};
    if numel(dtSeg) < 5
        continue;
    end
    [bytesAll, baudBest, scoreBest] = decode_segment_with_baud_search(dtSeg, 2400);
    scorePerByte = scoreBest / max(1, numel(bytesAll));
    if isempty(bytesAll)
        continue;
    end
    % Parse protocol messages in bytesAll
    i = 1;
    while i <= numel(bytesAll)
        b0 = bytesAll(i);
        if b0 == uint8('X')
            rows(end+1) = struct( ...
                'StartTime_us', segStart_us(s), ...
                'StartTime_s', segStart_us(s)/1e6, ...
                'Baud', baudBest, ...
                'Score', scorePerByte, ...
                'Type', "X", ...
                'Line', "X", ...
                'Bytes', {uint8('X')} ); %#ok<AGROW>
            i = i + 1;
            continue;
        end
        if b0 == uint8('T') || b0 == uint8('P')
            lfRel = find(bytesAll(i:end) == 10, 1, 'first');
            if isempty(lfRel)
                break;
            end
            msgBytes = bytesAll(i:i+lfRel-1);
            txt = char(msgBytes(:)).';
            lineStr = string(replace(txt, newline, "\n"));
            rows(end+1) = struct( ...
                'StartTime_us', segStart_us(s), ...
                'StartTime_s', segStart_us(s)/1e6, ...
                'Baud', baudBest, ...
                'Score', scorePerByte, ...
                'Type', string(char(b0)), ...
                'Line', lineStr, ...
                'Bytes', {msgBytes} ); %#ok<AGROW>
            i = i + lfRel;
            continue;
        end
        i = i + 1;
    end
end
Lines = struct2table(rows);
Lines = sortrows(Lines, 'StartTime_us');
disp(Lines(1:height(Lines), {'StartTime_s','Baud','Score','Type','Line'}));
%% ===================== Local function ===================== %%
function [bytesBest, baudBest, scoreBest] = decode_segment_with_baud_search(dtSeg, baud_nom)
    baudGrid = linspace(baud_nom*0.95, baud_nom*1.05, 41);
    bytesBest = uint8([]);
    baudBest  = baud_nom;
    scoreBest = -Inf;
    for baud = baudGrid
        Tb_us = 1e6/baud;
        bits = expand_dt_to_bits(dtSeg, Tb_us);
        % boundary padding (idle high outside)
        frameLen = 10;
        bitsP = [1; bits(:); ones(frameLen,1)];
        % --- NEW: try offsets 0..9 bits ---
        for off = 0:9
            b = uart_decode_bits_boundaryaware(bitsP(1+off:end), 8, 1);
            sc = score_bytes_protocol(b);
            if sc > scoreBest
                scoreBest = sc;
                bytesBest = b;
                baudBest  = baud;
            end
        end
    end
end
function bits = expand_dt_to_bits(dtSeg, Tb_us)
    state = 0;   % interval after an edge; assume first interval LOW (works well for your data)
    err = 0;
    bits = zeros(0,1);
    for k = 1:numel(dtSeg)
        dt_eff = dtSeg(k) + err;
        nBits = max(1, round(dt_eff / Tb_us));
        err = dt_eff - nBits*Tb_us;
        bits = [bits; repmat(state, nBits, 1)]; %#ok<AGROW>
        state = 1 - state;
    end
end
function bytes = uart_decode_bits_boundaryaware(bits, nDataBits, nStopBits)
    bits = bits(:);
    frameLen = 1 + nDataBits + nStopBits;
    bits = [1; bits; ones(frameLen,1)];
    bytes = uint8([]);
    i = 2;
    while i + frameLen - 1 <= numel(bits)
        if ~(bits(i-1)==1 && bits(i)==0)
            i = i + 1; continue;
        end
        dataBits = bits(i+1:i+nDataBits);
        stopBits = bits(i+nDataBits+1:i+nDataBits+nStopBits);
        if any(stopBits ~= 1)
            i = i + 1; continue;
        end
        val = uint8(0);
        for b = 1:nDataBits
            if dataBits(b), val = bitor(val, bitshift(uint8(1), b-1)); end
        end
        bytes(end+1,1) = val; %#ok<AGROW>
        i = i + frameLen;
    end
end
function sc = score_bytes_protocol(b)
    if isempty(b)
        sc = -Inf; return;
    end
    % Base: reward printable protocol alphabet
    isLetter = (b>=65 & b<=90) | (b>=97 & b<=122);
    isDigit  = (b>=48 & b<=57);
    isUnder  = (b==95);
    isLF     = (b==10);
    isCR     = (b==13);
    sc = sum(isLetter | isDigit | isUnder | isLF | isCR);
    % Penalize high-bit garbage
    sc = sc - 3*sum(b >= 128);
    % Strong preference for valid message starts
    if any(b(1) == uint8(['T','P','X']))
        sc = sc + 30;
    else
        sc = sc - 20;
    end
    % If it begins with T, reward T####\n specifically
    if b(1) == uint8('T')
        if numel(b) >= 6 && all(b(2:5) >= 48 & b(2:5) <= 57)
            sc = sc + 40;
            if any(b == 10), sc = sc + 10; end
        else
            sc = sc - 15;
        end
    end
    % If it begins with P, reward having an LF somewhere soon
    if b(1) == uint8('P')
        lf = find(b==10, 1);
        if ~isempty(lf) && lf <= 120
            sc = sc + 25;
        end
    end
    % If it begins with X, reward being short (since X has no \n)
    if b(1) == uint8('X')
        sc = sc + 10 - 0.5*min(numel(b), 40);
    end
end
function dt_clean = glitch_merge_dt(dt_us, Tb_us, minFrac)
% Merge intervals shorter than minFrac*Tb by combining with the next interval.
% This effectively removes an edge pair caused by a glitch.
    if nargin < 3, minFrac = 0.2; end
    min_us = minFrac * Tb_us;
    dt_clean = dt_us(:);
    k = 1;
    while k <= numel(dt_clean)
        if dt_clean(k) < min_us
            if k < numel(dt_clean)
                dt_clean(k+1) = dt_clean(k) + dt_clean(k+1);
            end
            dt_clean(k) = [];
            % don't advance k; re-check new dt_clean(k)
        else
            k = k + 1;
        end
    end
end
