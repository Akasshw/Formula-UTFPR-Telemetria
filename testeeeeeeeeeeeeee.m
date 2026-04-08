clear
clc

%% ===== MQTT CONFIG =====
brokerAddress = "tcp://mrrpformula.ddns.net";
port          = 1883;
client        = mqttclient(brokerAddress, Port=port, Username="client", Password="client_futfpr");
subscribe(client, "sensors");
disp("Conectado ao broker.")

%% ===== MAPEAMENTO DE SENSORES =====
SENSOR_IDS   = {'A','B','C','D','E','F','G','H','I','J'};
SENSOR_NAMES = {'rpm','steering_angle','oil_temp','speed','throttle', ...
                'brake','gear','water_temp','voltage','fuel_level'};
numTotal     = length(SENSOR_IDS);

allSensors = cell(numTotal, 2);
for i = 1:numTotal
    allSensors{i,1} = SENSOR_IDS{i};
    allSensors{i,2} = SENSOR_NAMES{i};
end

fprintf('Sensores configurados (%d):\n', numTotal)
for i = 1:numTotal
    fprintf('  [%d] %s (%s)\n', i, allSensors{i,2}, allSensors{i,1})
end

%% ===== CSV UNICO =====
% Colunas: time_s, lap_id, lap_time_s, <sensores...>
%   lap_id=0     -> dado fora de volta (sessao geral)
%   lap_id=N>0   -> dado pertencente a volta N
%   lap_time_s   -> tempo relativo ao inicio da volta (0 se fora de volta)
sessionTag = datestr(now,'yyyy-mm-dd_HH-MM-SS');
csvFile    = ['telemetry_log_' sessionTag '.csv'];
csvHeader  = false;

%% ===== VARIAVEIS TEMPO REAL =====
windowSize       = 30;
cursorPos        = 0.70;
pastWindow       = windowSize * cursorPos;
futureWindow     = windowSize * (1 - cursorPos);
sessionStartUnix = [];
lastPlotTime     = tic;
timeBuffer       = [];
dataBuffer       = cell(1, numTotal);
lastValues       = nan(1, numTotal);
for i = 1:numTotal, dataBuffer{i} = []; end

lineColors = lines(numTotal);
ax         = [];
h          = {};
grupos     = {};

%% ===== ESTADO COMPARTILHADO =====
sharedState = containers.Map( ...
    {'applySelection', 'applyLapPlot'}, ...
    {true,              false          });

lapState = containers.Map();
lapState('voltas')        = {};
lapState('voltaAtiva')    = false;
lapState('voltaStart_t')  = 0;
lapState('lapNum')        = 0;

MAX_GROUPS = 5;

%% ===== LAYOUT DA JANELA DE CONTROLE =====
WIN_W       = 300;
WIN_H       = 680;
CHK_COLS    = 2;
CHK_H       = 20;
CHK_GAP     = 2;
GRP_LABEL_H = 22;
GRP_PAD     = 8;
BOTTOM_BAR  = 130;
colW        = floor((WIN_W - 36) / CHK_COLS);

rowsPerGrp       = ceil(numTotal / CHK_COLS);
GRP_INNER_H      = rowsPerGrp * (CHK_H + CHK_GAP);
GRP_TOTAL_H      = GRP_LABEL_H + GRP_INNER_H + GRP_PAD;
SCROLL_CONTENT_H = MAX_GROUPS * GRP_TOTAL_H + 10;
scrollH          = WIN_H - 36 - BOTTOM_BAR - 4;

ctrlFig = uifigure('Name','Configuracao', ...
    'Position',[30 60 WIN_W WIN_H], 'Resize','off');

tabGroup = uitabgroup(ctrlFig, 'Position',[0 0 WIN_W WIN_H]);
tabRT    = uitab(tabGroup, 'Title','Tempo Real');
tabLap   = uitab(tabGroup, 'Title','Voltas');

%% ===== ABA TEMPO REAL =====
uilabel(tabRT, 'Text','Sensores por Grafico', ...
    'FontSize',11,'FontWeight','bold','HorizontalAlignment','center', ...
    'Position',[0 scrollH+BOTTOM_BAR-10 WIN_W 28]);

scrollPanel = uipanel(tabRT, ...
    'Position',[4 BOTTOM_BAR+4 WIN_W-8 scrollH-30], ...
    'Scrollable','on','BorderType','line');

innerPanel = uipanel(scrollPanel, ...
    'Position',[0 0 WIN_W-28 SCROLL_CONTENT_H], ...
    'BorderType','none','BackgroundColor',scrollPanel.BackgroundColor);

grpChk   = cell(1, MAX_GROUPS);
grpLabel = gobjects(1, MAX_GROUPS);

for g = 1:MAX_GROUPS
    grpTop = SCROLL_CONTENT_H - (g-1)*GRP_TOTAL_H - 6;
    grpLabel(g) = uilabel(innerPanel, ...
        'Text',sprintf('-- Grafico %d --',g), ...
        'FontSize',9,'FontWeight','bold', ...
        'Position',[4 grpTop-GRP_LABEL_H WIN_W-36 GRP_LABEL_H], ...
        'Visible','off');
    grpChk{g} = gobjects(1, numTotal);
    for i = 1:numTotal
        row  = ceil(i/CHK_COLS) - 1;
        col  = mod(i-1, CHK_COLS);
        xPos = 4 + col*colW;
        yPos = grpTop - GRP_LABEL_H - (row+1)*(CHK_H+CHK_GAP);
        grpChk{g}(i) = uicheckbox(innerPanel, ...
            'Text',allSensors{i,2},'Value',0,'FontSize',8, ...
            'Position',[xPos yPos colW-4 CHK_H],'Visible','off');
    end
end

grpLabel(1).Visible = 'on';
for i = 1:numTotal, grpChk{1}(i).Visible = 'on'; end
grpChk{1}(1).Value = 1;

lblGraficos = uilabel(tabRT, 'Text','Graficos ativos: 1', ...
    'FontSize',8,'HorizontalAlignment','center', ...
    'Position',[4 BOTTOM_BAR-18 WIN_W-8 18]);

uibutton(tabRT,'Text','+ Novo Grafico', ...
    'FontSize',9,'FontWeight','bold', ...
    'BackgroundColor',[0.2 0.4 0.8],'FontColor','white', ...
    'Position',[4 BOTTOM_BAR-50 (WIN_W-12)/2 28], ...
    'ButtonPushedFcn',@(~,~) cbNovoGrafico(ctrlFig,grpLabel,grpChk,numTotal,MAX_GROUPS,lblGraficos));

uibutton(tabRT,'Text','- Remover Grafico', ...
    'FontSize',9,'FontWeight','bold', ...
    'BackgroundColor',[0.7 0.2 0.2],'FontColor','white', ...
    'Position',[8+(WIN_W-12)/2 BOTTOM_BAR-50 (WIN_W-12)/2 28], ...
    'ButtonPushedFcn',@(~,~) cbRemoverGrafico(ctrlFig,grpLabel,grpChk,numTotal,MAX_GROUPS,lblGraficos));

uibutton(tabRT,'Text','Aplicar', ...
    'FontSize',10,'FontWeight','bold', ...
    'BackgroundColor',[0.2 0.6 0.2],'FontColor','white', ...
    'Position',[4 BOTTOM_BAR-86 WIN_W-8 32], ...
    'ButtonPushedFcn',@(~,~) cbAplicar(ctrlFig,grpChk,sharedState,numTotal));

ctrlFig.UserData = struct('numGrpsRT', 1, 'numGrpsLap', 1);

%% ===== ABA VOLTAS =====
LAPS_PANEL_H = 180;
LAP_BTN_Y    = WIN_H - 80;

btnIniciar = uibutton(tabLap, 'Text','▶  Iniciar Volta', ...
    'FontSize',10,'FontWeight','bold', ...
    'BackgroundColor',[0.1 0.6 0.1],'FontColor','white', ...
    'Position',[4 LAP_BTN_Y-30 (WIN_W-12)/2 34]);

btnFinalizar = uibutton(tabLap, 'Text','■  Finalizar Volta', ...
    'FontSize',10,'FontWeight','bold', ...
    'BackgroundColor',[0.6 0.1 0.1],'FontColor','white', ...
    'Position',[8+(WIN_W-12)/2 LAP_BTN_Y-30 (WIN_W-12)/2 34], ...
    'Enable','off');

lblLapStatus = uilabel(tabLap, 'Text','Nenhuma volta em andamento', ...
    'FontSize',8,'HorizontalAlignment','center', ...
    'FontColor',[0.5 0.5 0.5], ...
    'Position',[4 LAP_BTN_Y-52 WIN_W-8 18]);

uilabel(tabLap,'Text','Voltas registradas nesta sessao:', ...
    'FontSize',9,'FontWeight','bold', ...
    'Position',[4 LAP_BTN_Y-76 WIN_W-8 18]);

lapTable = uitable(tabLap, ...
    'Position',[4 LAP_BTN_Y-76-LAPS_PANEL_H WIN_W-8 LAPS_PANEL_H], ...
    'ColumnName',{'Volta','Inicio (s)','Fim (s)','Tempo (s)'}, ...
    'ColumnWidth',{42, 64, 64, 80}, ...
    'RowName',{}, ...
    'Data',{}, ...
    'ColumnEditable',[false false false false], ...
    'FontSize',8);

lapScrollY  = 10;
lapScrollH  = LAP_BTN_Y - 76 - LAPS_PANEL_H - 140;

uilabel(tabLap,'Text','Sensores para plotar (grafico MATLAB):', ...
    'FontSize',9,'FontWeight','bold', ...
    'Position',[4 lapScrollY+lapScrollH+86 WIN_W-8 18]);

lapScrollPanel = uipanel(tabLap, ...
    'Position',[4 lapScrollY+60 WIN_W-8 lapScrollH], ...
    'Scrollable','on','BorderType','line');

lapInnerPanel = uipanel(lapScrollPanel, ...
    'Position',[0 0 WIN_W-28 SCROLL_CONTENT_H], ...
    'BorderType','none','BackgroundColor',lapScrollPanel.BackgroundColor);

lapGrpChk   = cell(1, MAX_GROUPS);
lapGrpLabel = gobjects(1, MAX_GROUPS);

for g = 1:MAX_GROUPS
    grpTop = SCROLL_CONTENT_H - (g-1)*GRP_TOTAL_H - 6;
    lapGrpLabel(g) = uilabel(lapInnerPanel, ...
        'Text',sprintf('-- Grafico %d --',g), ...
        'FontSize',9,'FontWeight','bold', ...
        'Position',[4 grpTop-GRP_LABEL_H WIN_W-36 GRP_LABEL_H], ...
        'Visible','off');
    lapGrpChk{g} = gobjects(1, numTotal);
    for i = 1:numTotal
        row  = ceil(i/CHK_COLS) - 1;
        col  = mod(i-1, CHK_COLS);
        xPos = 4 + col*colW;
        yPos = grpTop - GRP_LABEL_H - (row+1)*(CHK_H+CHK_GAP);
        lapGrpChk{g}(i) = uicheckbox(lapInnerPanel, ...
            'Text',allSensors{i,2},'Value',0,'FontSize',8, ...
            'Position',[xPos yPos colW-4 CHK_H],'Visible','off');
    end
end

lapGrpLabel(1).Visible = 'on';
for i = 1:numTotal, lapGrpChk{1}(i).Visible = 'on'; end
lapGrpChk{1}(1).Value = 1;

lblLapGraficos = uilabel(tabLap, 'Text','Graficos: 1', ...
    'FontSize',8,'HorizontalAlignment','center', ...
    'Position',[4 lapScrollY+42 WIN_W-8 16]);

uibutton(tabLap,'Text','+ Grafico', ...
    'FontSize',8,'FontWeight','bold', ...
    'BackgroundColor',[0.2 0.4 0.8],'FontColor','white', ...
    'Position',[4 lapScrollY+18 (WIN_W-12)/3 22], ...
    'ButtonPushedFcn',@(~,~) cbNovoGraficoLap(ctrlFig,lapGrpLabel,lapGrpChk,numTotal,MAX_GROUPS,lblLapGraficos));

uibutton(tabLap,'Text','- Grafico', ...
    'FontSize',8,'FontWeight','bold', ...
    'BackgroundColor',[0.7 0.2 0.2],'FontColor','white', ...
    'Position',[8+(WIN_W-12)/3 lapScrollY+18 (WIN_W-12)/3 22], ...
    'ButtonPushedFcn',@(~,~) cbRemoverGraficoLap(ctrlFig,lapGrpLabel,lapGrpChk,numTotal,MAX_GROUPS,lblLapGraficos));

uibutton(tabLap,'Text','Plotar Voltas', ...
    'FontSize',8,'FontWeight','bold', ...
    'BackgroundColor',[0.2 0.6 0.2],'FontColor','white', ...
    'Position',[12+2*(WIN_W-12)/3 lapScrollY+18 (WIN_W-12)/3 22], ...
    'ButtonPushedFcn',@(~,~) cbAplicarLap(ctrlFig,lapGrpChk,sharedState,numTotal));

btnIniciar.ButtonPushedFcn   = @(~,~) cbIniciarVolta(lapState,ctrlFig,btnIniciar,btnFinalizar,lblLapStatus);
btnFinalizar.ButtonPushedFcn = @(~,~) cbFinalizarVolta(lapState,ctrlFig,btnIniciar,btnFinalizar,lblLapStatus,lapTable);

%% ===== FIGURA DE GRAFICOS =====
plotFig = figure('Name','Telemetria — Tempo Real', ...
    'NumberTitle','off','Position',[340 60 980 660]);

%% ===== LOOP PRINCIPAL =====
while ishandle(plotFig) && isvalid(ctrlFig)

    msg = read(client);

    for m = 1:height(msg)
        raw = strtrim(char(msg.Data(m)));
        parts       = strsplit(raw, '|');
        unixMsg     = [];
        sensorParts = {};

        for p = 1:length(parts)
            seg = parts{p};
            if isempty(seg), continue; end
            if startsWith(seg, 'T~')
                unixMsg = str2double(seg(3:end));
            else
                sensorParts{end+1} = seg;
            end
        end

        if isempty(unixMsg)
            unixMsg = posixtime(datetime('now','TimeZone','UTC'));
        end
        if isempty(sessionStartUnix)
            sessionStartUnix = unixMsg;
        end

        t = unixMsg - sessionStartUnix;

        for sp = 1:length(sensorParts)
            seg      = sensorParts{sp};
            tildeIdx = strfind(seg,'~');
            if isempty(tildeIdx), continue; end
            sensorID = seg(1:tildeIdx(1)-1);
            encoded  = seg(tildeIdx(1)+1:end);
            value    = decodeSensorValue(encoded);
            for i = 1:numTotal
                if strcmp(sensorID, allSensors{i,1})
                    lastValues(i) = value; break
                end
            end
        end

        if any(~isnan(lastValues))
            timeBuffer(end+1) = t;
            for i = 1:numTotal
                dataBuffer{i}(end+1) = lastValues(i);
            end

            % Determina lap_id e lap_time_s
            currentLapId   = 0;
            currentLapTime = 0;
            if lapState('voltaAtiva')
                lapNum_cur = lapState('lapNum');
                % Define t0 da volta no primeiro ponto capturado
                if lapState('voltaStart_t') < 0
                    lapState('voltaStart_t') = t;
                end
                currentLapId   = lapNum_cur;
                currentLapTime = t - lapState('voltaStart_t');
                elapsed        = currentLapTime;
                lblLapStatus.Text      = sprintf('▶  Volta %d: %.1f s', lapNum_cur, elapsed);
                lblLapStatus.FontColor = [0.1 0.6 0.1];
            end

            % Escreve CSV unico
            if ~csvHeader
                fid = fopen(csvFile,'w');
                hdr = 'time_s,lap_id,lap_time_s';
                for i = 1:numTotal, hdr = [hdr ',' allSensors{i,2}]; end
                fprintf(fid,'%s\n',hdr);
                fclose(fid);
                csvHeader = true;
            end
            fid    = fopen(csvFile,'a');
            rowStr = sprintf('%.3f,%d,%.3f', t, currentLapId, currentLapTime);
            for i = 1:numTotal, rowStr = [rowStr sprintf(',%g',lastValues(i))]; end
            fprintf(fid,'%s\n',rowStr);
            fclose(fid);
        end
    end

    %% Aplica selecao tempo real
    if sharedState('applySelection')
        sharedState('applySelection') = false;
        numGrps = ctrlFig.UserData.numGrpsRT;
        grupos  = cell(1, numGrps);
        for g = 1:numGrps
            sel = [];
            for i = 1:numTotal
                if isvalid(grpChk{g}(i)) && grpChk{g}(i).Value
                    sel(end+1) = i;
                end
            end
            grupos{g} = sel;
        end
        validos = ~cellfun(@isempty, grupos);
        grupos  = grupos(validos);
        numGrps = length(grupos);
        if numGrps == 0, disp('Nenhum sensor selecionado.'); continue; end

        figure(plotFig); clf(plotFig)
        ax = gobjects(1, numGrps);
        h  = cell(1, numGrps);
        for g = 1:numGrps
            ax(g) = subplot(numGrps,1,g,'Parent',plotFig);
            hold(ax(g),'on'); grid(ax(g),'on')
            sensorIdx   = grupos{g};
            h{g}        = gobjects(1,length(sensorIdx));
            legendNames = {};
            for k = 1:length(sensorIdx)
                i        = sensorIdx(k);
                h{g}(k)  = animatedline(ax(g),'Color',lineColors(i,:),'LineWidth',1.3);
                legendNames{end+1} = allSensors{i,2};
            end
            title(ax(g), strjoin(legendNames,' / '))
            if length(sensorIdx) > 1
                legend(ax(g),legendNames,'Location','northwest','FontSize',7)
            end
            ylabel(ax(g),'---')
            if g == numGrps, xlabel(ax(g),'Time (s)'), end
        end
    end

    %% Plota voltas (grafico MATLAB estatico)
    if sharedState('applyLapPlot')
        sharedState('applyLapPlot') = false;
        voltas = lapState('voltas');
        if isempty(voltas)
            uialert(ctrlFig,'Nenhuma volta registrada ainda.','Aviso')
        else
            numGrpsLap = ctrlFig.UserData.numGrpsLap;
            gruposLap  = cell(1, numGrpsLap);
            for g = 1:numGrpsLap
                sel = [];
                for i = 1:numTotal
                    if isvalid(lapGrpChk{g}(i)) && lapGrpChk{g}(i).Value
                        sel(end+1) = i;
                    end
                end
                gruposLap{g} = sel;
            end
            validos    = ~cellfun(@isempty, gruposLap);
            gruposLap  = gruposLap(validos);
            numGrpsLap = length(gruposLap);
            if numGrpsLap == 0
                uialert(ctrlFig,'Selecione ao menos um sensor.','Aviso')
            else
                lapColors = lines(length(voltas));
                lapFig    = figure('Name','Analise de Voltas','NumberTitle','off','Position',[340 60 980 660]);
                for g = 1:numGrpsLap
                    axL = subplot(numGrpsLap,1,g,'Parent',lapFig);
                    hold(axL,'on'); grid(axL,'on')
                    sensorIdx = gruposLap{g};
                    for vi = 1:length(voltas)
                        v     = voltas{vi};
                        tNorm = v.time - v.time(1);
                        for k = 1:length(sensorIdx)
                            si = sensorIdx(k);
                            if length(v.data{si}) == length(tNorm)
                                plot(axL,tNorm,v.data{si},'Color',lapColors(vi,:),'LineWidth',1.4, ...
                                    'DisplayName',sprintf('V%d – %s (%.2fs)',vi,allSensors{si,2},v.lapTime));
                            end
                        end
                    end
                    legend(axL,'Location','northwest','FontSize',7)
                    ylabel(axL, allSensors{gruposLap{g}(1),2})
                    if g == numGrpsLap, xlabel(axL,'Tempo na volta (s)'), end
                end
                [~,bestIdx] = min(cellfun(@(vv) vv.lapTime, voltas));
                sgtitle(lapFig,sprintf('%d volta(s)  |  Melhor: V%d (%.2fs)',length(voltas),bestIdx,voltas{bestIdx}.lapTime),'FontSize',10)
            end
        end
    end

    %% Atualiza plots tempo real
    if toc(lastPlotTime) >= 0.15 && ~isempty(ax) && ~isempty(grupos)
        if length(timeBuffer) > 2
            tNow = timeBuffer(end);
            xMin = tNow - pastWindow;
            xMax = tNow + futureWindow;
            idx  = timeBuffer >= xMin;
            for g = 1:length(grupos)
                sensorIdx = grupos{g};
                for k = 1:length(sensorIdx)
                    i = sensorIdx(k);
                    if ishandle(h{g}(k))
                        clearpoints(h{g}(k))
                        addpoints(h{g}(k), timeBuffer(idx), dataBuffer{i}(idx))
                    end
                end
                if ishandle(ax(g)), xlim(ax(g),[xMin xMax]), end
            end
            timeBuffer = timeBuffer(idx);
            for i = 1:numTotal, dataBuffer{i} = dataBuffer{i}(idx); end
            drawnow limitrate
        end
        lastPlotTime = tic;
    end

end
disp('Receiver encerrado.')

%% ===== CALLBACKS =====
function cbIniciarVolta(lapState, ~, btnIniciar, btnFinalizar, lblLapStatus)
    lapNum = lapState('lapNum') + 1;
    lapState('lapNum')       = lapNum;
    lapState('voltaAtiva')   = true;
    lapState('voltaStart_t') = -1;
    btnIniciar.Enable        = 'off';
    btnFinalizar.Enable      = 'on';
    lblLapStatus.Text        = sprintf('▶  Volta %d em andamento: 0.0 s', lapNum);
    lblLapStatus.FontColor   = [0.1 0.6 0.1];
    fprintf('Volta %d iniciada.\n', lapNum)
end

function cbFinalizarVolta(lapState, ~, btnIniciar, btnFinalizar, lblLapStatus, lapTable)
    lapState('voltaAtiva') = false;
    lapNum   = lapState('lapNum');
    tStart   = lapState('voltaStart_t');
    voltas   = lapState('voltas');

    % Registra metadado (tempo real calculado no Python)
    v.lapNum = lapNum;
    v.tStart = tStart;
    voltas{end+1} = v;
    lapState('voltas') = voltas;

    btnIniciar.Enable      = 'on';
    btnFinalizar.Enable    = 'off';
    lblLapStatus.Text      = sprintf('Volta %d finalizada', lapNum);
    lblLapStatus.FontColor = [0.2 0.2 0.8];

    tableData = cell(length(voltas), 4);
    for vi = 1:length(voltas)
        tableData{vi,1} = voltas{vi}.lapNum;
        tableData{vi,2} = sprintf('%.2f', voltas{vi}.tStart);
        tableData{vi,3} = '—';
        tableData{vi,4} = '—';
    end
    lapTable.Data = tableData;
    fprintf('Volta %d finalizada.\n', lapNum)
end

function value = decodeSensorValue(encoded)
    binStr = '';
    for c = 1:length(encoded)
        decVal = double(encoded(c)) - 32;
        block  = dec2bin(decVal, 6);
        binStr = [binStr block];
    end
    value = bin2dec(binStr);
end

function cbNovoGrafico(ctrlFig, grpLabel, grpChk, numTotal, maxG, lblGraficos)
    s = ctrlFig.UserData;
    if s.numGrpsRT >= maxG, uialert(ctrlFig,sprintf('Maximo de %d graficos.',maxG),'Aviso'); return, end
    novo = s.numGrpsRT + 1; s.numGrpsRT = novo; ctrlFig.UserData = s;
    grpLabel(novo).Visible = 'on';
    for i = 1:numTotal, grpChk{novo}(i).Visible = 'on'; end
    lblGraficos.Text = sprintf('Graficos ativos: %d', novo);
end

function cbRemoverGrafico(ctrlFig, grpLabel, grpChk, numTotal, ~, lblGraficos)
    s = ctrlFig.UserData;
    if s.numGrpsRT <= 1, uialert(ctrlFig,'Minimo de 1 grafico.','Aviso'); return, end
    grpLabel(s.numGrpsRT).Visible = 'off';
    for i = 1:numTotal, grpChk{s.numGrpsRT}(i).Visible = 'off'; end
    s.numGrpsRT = s.numGrpsRT - 1; ctrlFig.UserData = s;
    lblGraficos.Text = sprintf('Graficos ativos: %d', s.numGrpsRT);
end

function cbAplicar(ctrlFig, grpChk, sharedState, numTotal)
    s = ctrlFig.UserData; hasAny = false;
    for g = 1:s.numGrpsRT
        for i = 1:numTotal
            if isvalid(grpChk{g}(i)) && grpChk{g}(i).Value, hasAny = true; break, end
        end
        if hasAny, break, end
    end
    if ~hasAny, uialert(ctrlFig,'Selecione pelo menos um sensor.','Aviso'); return, end
    sharedState('applySelection') = true;
end

function cbNovoGraficoLap(ctrlFig, grpLabel, grpChk, numTotal, maxG, lblGraficos)
    s = ctrlFig.UserData;
    if s.numGrpsLap >= maxG, uialert(ctrlFig,sprintf('Maximo de %d graficos.',maxG),'Aviso'); return, end
    novo = s.numGrpsLap + 1; s.numGrpsLap = novo; ctrlFig.UserData = s;
    grpLabel(novo).Visible = 'on';
    for i = 1:numTotal, grpChk{novo}(i).Visible = 'on'; end
    lblGraficos.Text = sprintf('Graficos: %d', novo);
end

function cbRemoverGraficoLap(ctrlFig, grpLabel, grpChk, numTotal, ~, lblGraficos)
    s = ctrlFig.UserData;
    if s.numGrpsLap <= 1, uialert(ctrlFig,'Minimo de 1 grafico.','Aviso'); return, end
    grpLabel(s.numGrpsLap).Visible = 'off';
    for i = 1:numTotal, grpChk{s.numGrpsLap}(i).Visible = 'off'; end
    s.numGrpsLap = s.numGrpsLap - 1; ctrlFig.UserData = s;
    lblGraficos.Text = sprintf('Graficos: %d', s.numGrpsLap);
end

function cbAplicarLap(ctrlFig, lapGrpChk, sharedState, numTotal)
    s = ctrlFig.UserData; hasAny = false;
    for g = 1:s.numGrpsLap
        for i = 1:numTotal
            if isvalid(lapGrpChk{g}(i)) && lapGrpChk{g}(i).Value, hasAny = true; break, end
        end
        if hasAny, break, end
    end
    if ~hasAny, uialert(ctrlFig,'Selecione pelo menos um sensor.','Aviso'); return, end
    sharedState('applyLapPlot') = true;
end