%% Folder location
cd('Z:\RCP_Data\EMU\RCP_CUA_E001\Neuralynx\NWB_Data')


%% Session of interest
sessOfInt = 'RCP_EMU_1_Session_7_filter.nwb';


%% NWB Schema
addpath(genpath('C:\Users\Admin\Documents\MATLAB\matnwb-2.10.0'))


%% Load in NWB
sessNwb = nwbRead(sessOfInt);

%% NWB parts

ttlVals = sessNwb.acquisition.get('events').data.load();
ttlTimes = sessNwb.acquisition.get('events').timestamps.load();
%% TTL

% Process TTL values and times for further analysis
ttlData = table(ttlTimes, ttlVals, 'VariableNames', {'Time', 'Value'});

% ttlData = ttlData(~contains(ttlData.Value,{'Starting','value'}),:);

%%

plot(ttlData.Time)


%%
