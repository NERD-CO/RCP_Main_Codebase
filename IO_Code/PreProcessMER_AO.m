function [] = PreProcessMER_AO(mat_filelist, RawDataDir)

% hardcode directories

cd(RawDataDir)
ProcDataDir = [RawDataDir, filesep, 'Processed Electrophysiology']; 

if ~exist(ProcDataDir,'dir')
    mkdir(ProcDataDir); 
end

% navigate to directory where raw MATLAB data files are located
cd(RawDataDir)

% extract relevant info from relevant .mat files in mat_filelist
for i = 1:length(mat_filelist)

    % Added 7/31/2023
    cd(RawDataDir)

    tmpFilename = mat_filelist{i};          
    matFileInfo = matfile(tmpFilename);    
    matFileVars1 = whos(matFileInfo);      
    matFileVars2 = {matFileVars1.name};     

    % list Ephys filetypes of interest (conditions)
    ftypes = {'CSPK', 'CLFP', 'CMacro_LFP', 'CDIG'}; % 'CEMG'

    % isolate fields of interest per filetype
    for f = 1:length(ftypes) % 1:6
        Ftype = ftypes{f};

        outStruct = getFILEinfo(Ftype, matFileVars2, tmpFilename); % 

        switch Ftype
            case 'CSPK'
                % 1. Find all spike files and extract relevant fields via getFILEinfo
                % save to outStruct
                ProcEphys.Spike = outStruct;

            case 'CLFP'
                % 2. Find all LFP files and extract relevant fields via getFILEinfo
                % save to outStruct
                ProcEphys.LFP = outStruct;

            case 'CMacro_LFP'
                % 3. Find all mLFP files and extract relevant fields via getFILEinfo
                % save to outStruct
                ProcEphys.MLFP = outStruct;

            case 'CDIG'
                % 4. Find all TTL files and extract relevant fields via getFILEinfo
                % save to outStruct
                ProcEphys.TTL = outStruct;
   
        end

    end

    % save into new directory with new name
    saveName = ['Processed_',tmpFilename];
    cd(ProcDataDir)
    save(saveName,'ProcEphys');

end
end


%% helper functions

function [outStruct] = getFILEinfo(fTYPE, varITEMS, mfname)

switch fTYPE

    case {'CSPK','CLFP','CMacro_LFP', 'CEMG'} % add EMG and ACC ftypes to this case later
        indiCES = contains(varITEMS, fTYPE); % find relevant fields of ftype
        % Get list
        varLIST = varITEMS(indiCES);
        % how many micro electrodes
        % Get info between '-'
        eleContent = extract(varLIST,digitsPattern); % digitsPatterns - look for all pos. dig. in string
        eleIDs = extractAfter(unique(eleContent),1);
        wholeEleID = unique(eleContent);

        % Debugging - print eleIDs
        disp(['eleIDs: ', strjoin(eleIDs, ', ')]);
        % return an empty struct if eleIDs is empty
        if isempty(eleIDs)
            outStruct = struct;
            return
        end

        for ei = 1:numel(wholeEleID) % numel - # of elements in array
            % Hz
            [freqItem] = getVARid(varLIST, wholeEleID{ei}, fTYPE, '_KHz');
            [varFreq] = extractVarName(mfname,freqItem);
            outStruct.(['E',num2str(eleIDs{ei})]).Hz = varFreq;

            % Raw data
            [dataItem] = getVARid(varLIST, wholeEleID{ei}, fTYPE, '');
            [varData] = extractVarName(mfname,dataItem);
            outStruct.(['E',num2str(eleIDs{ei})]).rawData = varData;

            % Start time
            [startTitem] = getVARid(varLIST, wholeEleID{ei}, fTYPE, '_TimeBegin');
            [varStime] = extractVarName(mfname,startTitem);
            outStruct.(['E',num2str(eleIDs{ei})]).startTime = varStime;
            % End time

            [endTitem] = getVARid(varLIST, wholeEleID{ei}, fTYPE, '_TimeEnd');
            [varEtime] = extractVarName(mfname,endTitem);
            outStruct.(['E',num2str(eleIDs{ei})]).endTime = varEtime;
        end

    case 'CDIG'
        indiCES = contains(varITEMS, fTYPE);
        % Get list
        varLIST = varITEMS(indiCES);
        % Hz
        [freqItem] = getVARid(varLIST, 'IN_1', fTYPE, '_KHz');

        if isempty(freqItem)
            outStruct = nan;
        else

            [varFreq] = extractVarName(mfname,freqItem);
            outStruct.Hz = varFreq;

            % Down
            [downItem] = getVARid(varLIST, 'IN_1', fTYPE, '_Down');
            [varDown] = extractVarName(mfname,downItem);
            outStruct.Down = varDown;

            % Start time
            [startTitem] = getVARid(varLIST, 'IN_1', fTYPE, '_TimeBegin');
            [varStime] = extractVarName(mfname,startTitem);
            outStruct.startTime = varStime;

            % End time
            [endTitem] = getVARid(varLIST, 'IN_1', fTYPE, '_TimeEnd');
            [varEtime] = extractVarName(mfname,endTitem);
            outStruct.endTime = varEtime;
        end


end
end


function [varNAME] = getVARid(vLIST, wholeEleID, fTYPE1, fTYPE2)

% Debugging
% disp(['vLIST: ', strjoin(vLIST, ', ')]);
% disp(['wholeEleID: ', wholeEleID]);
% disp(['fTYPE1: ', fTYPE1]);
% disp(['fTYPE2: ', fTYPE2]);


    freqItem = vLIST(matches(vLIST,[fTYPE1, '_', wholeEleID, fTYPE2]));

    if ~isempty(vLIST) && contains(vLIST{1},'Central')
       freqItem = vLIST(contains(vLIST,[fTYPE1, '_', wholeEleID]) & contains(vLIST,fTYPE2));
    end

    if isempty(freqItem)
        warning('Variable list is empty. Returning empty varNAME');
        varNAME = [];
    else
        varNAME = freqItem{1};
    end


end



function [varExtract] = extractVarName(inMfname,inMvar)

tmpLoadF = load(inMfname,inMvar);
tmpLoadFns = fieldnames(tmpLoadF);
varExtract = tmpLoadF.(tmpLoadFns{1});

end
