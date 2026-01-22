clear; clc; close all;

% ================== CONFIGURAÇÃO INICIAL ==================
disp('Selecione o arquivo CSV de telemetria...');

% Abre diálogo para selecionar arquivo
[arquivo, caminho] = uigetfile('*.csv', 'Selecione o arquivo CSV');

if isequal(arquivo, 0)
    disp('❌ Nenhum arquivo selecionado');
    return
end

arquivoCompleto = fullfile(caminho, arquivo);
disp(['📂 Lendo: ' arquivo]);

% Extrair nome base do arquivo (sem extensão)
[~, nomeArquivo, ~] = fileparts(arquivo);

try
    % Lê o arquivo CSV
    data = readtable(arquivoCompleto, 'VariableNamingRule', 'preserve');
catch ME
    disp('❌ Erro ao ler arquivo CSV');
    disp(ME.message);
    return
end

colNames = data.Properties.VariableNames;
tempoCol = colNames{end};  % Última coluna é o tempo
colunasValidas = colNames(1:end-1);  % Todas exceto a última

disp(['✅ Arquivo carregado: ' num2str(height(data)) ' linhas, ' num2str(width(data)) ' colunas']);

menuPrincipal(data, tempoCol, colunasValidas, nomeArquivo);

%% ================= FUNÇÕES =================

% -------- MENU PRINCIPAL --------
function menuPrincipal(data, tempoCol, colunasValidas, nomeArquivo)

    f = uifigure('Name','Fórmula UTFPR',...
        'Position',[500 300 300 240]);

    uilabel(f,'Text','Escolha uma opção:',...
        'Position',[75 180 150 20],...
        'HorizontalAlignment','center');

    uibutton(f,'Text','Plotar Gráficos',...
        'Position',[75 130 150 40],...
        'ButtonPushedFcn',@(btn,event) abrirMenuPlot(f,data,tempoCol,colunasValidas,nomeArquivo));

    uibutton(f,'Text','Sair',...
        'Position',[75 60 150 40],...
        'ButtonPushedFcn',@(btn,event) close(f));
end

% -------- MENU DE PLOTAGEM --------
function abrirMenuPlot(fMain, data, tempoCol, colunasValidas, nomeArquivo)

    close(fMain);

    fPlot = uifigure('Name','Menu Plotagem - Estático',...
        'Position',[450 220 480 450]);

    fPlot.UserData.selecionados = {};
    fPlot.UserData.nomes = colunasValidas;
    fPlot.UserData.nomeArquivo = nomeArquivo;

    chk = uicheckbox(fPlot,...
        'Text','Selecionar vários gráficos (modo conjunto)',...
        'Position',[80 410 320 20],...
        'Value',false,...
        'ValueChangedFcn',@(chk,event) toggleModo(chk,fPlot));

    uilabel(fPlot,'Text','Escolha os dados para plotar:',...
        'Position',[130 385 250 20]);

    panelScroll = uipanel(fPlot,...
        'Position',[30 140 420 230],...
        'Scrollable','on');

    nCol = numel(colunasValidas);
    nLinhas = ceil(nCol/2);
    alturaInterna = nLinhas*40 + 20;

    panelInterno = uipanel(panelScroll,...
        'Position',[0 0 420 alturaInterna]);

    btnHandles = gobjects(1,nCol);

    for i = 1:nCol
        xpos = 20 + 200*mod(i-1,2);
        ypos = alturaInterna - 40*ceil(i/2);

        nome = colunasValidas{i};

        btnHandles(i) = uibutton(panelInterno,...
            'Text',nome,...
            'Position',[xpos ypos 180 30],...
            'ButtonPushedFcn',@(btn,event) selecionarGrafico(fPlot,data,tempoCol,nome));
    end

    btnConcluir = uibutton(fPlot,'Text','Concluir Seleção',...
        'Position',[70 75 160 35],...
        'Visible','off',...
        'ButtonPushedFcn',@(btn,event) concluirSelecao(fPlot,data,tempoCol));

    uibutton(fPlot,'Text','Plotar Todos',...
        'Position',[260 75 160 35],...
        'ButtonPushedFcn',@(btn,event) plotarTodos(fPlot,data,tempoCol));

    uibutton(fPlot,'Text','Salvar Dados Tratados',...
        'Position',[70 25 160 35],...
        'ButtonPushedFcn',@(btn,event) salvarDadosTratados(fPlot,data,tempoCol,colunasValidas,nomeArquivo));

    uibutton(fPlot,'Text','Voltar ao Menu',...
        'Position',[260 25 160 30],...
        'ButtonPushedFcn',@(btn,event) voltarMenu(fPlot,data,tempoCol,colunasValidas,nomeArquivo));

    fPlot.UserData.handles.chk = chk;
    fPlot.UserData.handles.btnConcluir = btnConcluir;
    fPlot.UserData.handles.btnHandles = btnHandles;
end

% -------- CONTROLE DO MODO --------
function toggleModo(chk,fPlot)

    fPlot.UserData.selecionados = {};

    if chk.Value
        fPlot.UserData.handles.btnConcluir.Visible = 'on';
    else
        fPlot.UserData.handles.btnConcluir.Visible = 'off';
    end

    for b = fPlot.UserData.handles.btnHandles
        if isgraphics(b)
            b.BackgroundColor = [0.94 0.94 0.94];
        end
    end
end

% -------- SELEÇÃO --------
function selecionarGrafico(fPlot,data,tempoCol,nome)

    modoConjunto = fPlot.UserData.handles.chk.Value;

    if ~modoConjunto
        abrirGrafico({nome},data,tempoCol,fPlot.UserData.nomeArquivo);
        return
    end

    lista = fPlot.UserData.selecionados;

    if ~ismember(nome,lista)
        lista{end+1} = nome;
    else
        lista(strcmp(lista,nome)) = [];
    end

    fPlot.UserData.selecionados = lista;

    for b = fPlot.UserData.handles.btnHandles
        if isgraphics(b) && strcmp(b.Text,nome)
            if ismember(nome,lista)
                b.BackgroundColor = [0.8 0.9 1];
            else
                b.BackgroundColor = [0.94 0.94 0.94];
            end
        end
    end
end

% -------- CONCLUIR --------
function concluirSelecao(fPlot,data,tempoCol)

    lista = fPlot.UserData.selecionados;

    if isempty(lista)
        uialert(fPlot,'Nenhum gráfico selecionado','Aviso');
        return
    end

    abrirGrafico(lista,data,tempoCol,fPlot.UserData.nomeArquivo);
end

% -------- PLOTAR TODOS --------
function plotarTodos(fPlot,data,tempoCol)

    abrirGrafico(fPlot.UserData.nomes,data,tempoCol,fPlot.UserData.nomeArquivo);
end

% -------- VOLTAR --------
function voltarMenu(fPlot,data,tempoCol,colunasValidas,nomeArquivo)

    close(fPlot);
    menuPrincipal(data,tempoCol,colunasValidas,nomeArquivo);
end

%% -------- OBTER AJUSTES DE ZERO POR ARQUIVO --------
function ajustes = obterAjustesZero(nomeArquivo)
    % Define os ajustes para cada arquivo/coluna
    % Usa apenas o prefixo do nome da coluna (sem o símbolo de grau)
    
    ajustes = struct();
    
    % DEBUG: Mostrar nome do arquivo
    disp(['🔍 DEBUG: Nome do arquivo = "' nomeArquivo '"']);
    
    % Detectar qual configuração usar baseado no nome do arquivo
    % Usado para deslocar os valores pra realocar o zero
    % Para usar basta mudar elseif contains(nomeArquivo, 'testXX',
    % 'IgnoreCase', true), sendo XX o número do arquivo de teste, por
    % exemplo, test05
    if contains(nomeArquivo, 'Kit Completo', 'IgnoreCase', true) || contains(nomeArquivo, 'KC', 'IgnoreCase', true)
        disp('✅ Detectado: Kit Completo (KC)');
        ajustes.Susp_Pos_FR = 66.8;
        ajustes.Susp_Pos_FL = 13.3;
        ajustes.Susp_Pos_RR = 0;
        ajustes.Susp_Pos_RL = -27.7;
        ajustes.SteerWheel = 0;
        
    elseif contains(nomeArquivo, 'Sem asa dianteira', 'IgnoreCase', true) || contains(nomeArquivo, 'SAD', 'IgnoreCase', true)
        disp('✅ Detectado: Sem asa dianteira (SAD)');
        ajustes.Susp_Pos_FR = 57.4;
        ajustes.Susp_Pos_FL = 18.6;
        ajustes.Susp_Pos_RR = 0;
        ajustes.Susp_Pos_RL = -26.9;
        ajustes.SteerWheel = 0;
        
    elseif contains(nomeArquivo, 'Sem KIT', 'IgnoreCase', true) || contains(nomeArquivo, 'SK', 'IgnoreCase', true)
        disp('✅ Detectado: Sem KIT (SK)');
        ajustes.Susp_Pos_FR = 66.8;
        ajustes.Susp_Pos_FL = 14.3;
        ajustes.Susp_Pos_RR = 0;
        ajustes.Susp_Pos_RL = -27.7;
        ajustes.SteerWheel = 0;
    elseif contains(nomeArquivo, 'test05', 'IgnoreCase', true)
        disp('✅ Detectado: teste 5');
        ajustes.Susp_Pos_FR = 0;
        ajustes.Susp_Pos_FL = 19.9;
        ajustes.Susp_Pos_RR = -0.6;
        ajustes.Susp_Pos_RL = -25.5;
        ajustes.SteerWheel = -48;
    elseif contains(nomeArquivo, 'test09', 'IgnoreCase', true)
        disp('✅ Detectado: teste 9');
        ajustes.Susp_Pos_FR = 0;
        ajustes.Susp_Pos_FL = 0;
        ajustes.Susp_Pos_RR = 0.1;
        ajustes.Susp_Pos_RL = -24.4;
        ajustes.SteerWheel = -50.2;
    elseif contains(nomeArquivo, 'test12', 'IgnoreCase', true)
        disp('✅ Detectado: teste 12');
        ajustes.Susp_Pos_FR = 0;
        ajustes.Susp_Pos_FL = 19.7;
        ajustes.Susp_Pos_RR = 0.3;
        ajustes.Susp_Pos_RL = -24.2;
        ajustes.SteerWheel = -46.5;
    elseif contains(nomeArquivo, 'test50', 'IgnoreCase', true)
        disp('✅ Detectado: teste 50');
        ajustes.Susp_Pos_FR = 67;
        ajustes.Susp_Pos_FL = 9;
        ajustes.Susp_Pos_RR = 0.4;
        ajustes.Susp_Pos_RL = -25.4;
        ajustes.SteerWheel = 0;
    else
        disp('⚠️  Nenhuma configuração específica encontrada - sem ajustes');
    end
    

end

%% -------- SALVAR DADOS TRATADOS --------
function salvarDadosTratados(fPlot,data,tempoCol,colunasValidas,nomeArquivo)
    
    % Pedir nome do arquivo
    [arquivo, caminho] = uiputfile('*.csv', 'Salvar dados tratados como');
    
    if isequal(arquivo, 0)
        return  % Usuário cancelou
    end
    
    arquivoCompleto = fullfile(caminho, arquivo);
    
    % Obter ajustes de zero para este arquivo
    ajustes = obterAjustesZero(nomeArquivo);
    
    % Criar tabela iniciando vazia
    dadosTratados = table();
    
    % Obter tempo
    t = data{:,tempoCol};
    
    % Verificar se tempo é numérico
    if ~isnumeric(t)
        uialert(fPlot, 'Coluna de tempo não é numérica!', 'Erro', 'Icon', 'error');
        return;
    end
    
    % Processar cada coluna NA ORDEM ORIGINAL
    h = waitbar(0, 'Processando dados...');
    colunasProcessadas = 0;
    
    for i = 1:numel(colunasValidas)
        waitbar(i/numel(colunasValidas), h, ['Processando: ' colunasValidas{i}]);
        
        nomeCol = colunasValidas{i};
        x_bruto = data.(nomeCol);
        
        % Se for numérico, trata e aplica ajuste
        if isnumeric(x_bruto)
            x_tratado = tratarSinalButterworth(x_bruto, t);
            
            % Aplicar ajuste de zero se existir
            ajuste_valor = buscarAjuste(nomeCol, ajustes);
            if ajuste_valor ~= 0
                x_tratado = x_tratado + ajuste_valor;
            end
            
            dadosTratados.(nomeCol) = x_tratado;
            colunasProcessadas = colunasProcessadas + 1;
        else
            % Copiar coluna não-numérica do original (como "gear")
            dadosTratados.(nomeCol) = x_bruto;
        end
    end
    
    % Adicionar coluna de tempo NO FINAL
    dadosTratados.(tempoCol) = t;
    
    close(h);
    
    if colunasProcessadas == 0
        uialert(fPlot, 'Nenhuma coluna numérica encontrada!', 'Erro', 'Icon', 'error');
        return;
    end
    
    % Salvar arquivo
    try
        writetable(dadosTratados, arquivoCompleto, 'FileType', 'text');
        uialert(fPlot, sprintf('Dados salvos!\n%d colunas processadas\nAjustes aplicados para: %s\nArquivo: %s', ...
                colunasProcessadas, nomeArquivo, arquivo), 'Sucesso', 'Icon', 'success');
    catch ME
        uialert(fPlot, ['Erro ao salvar: ' ME.message], 'Erro', 'Icon', 'error');
    end
end

%% -------- FUNÇÃO DE PLOT --------
function abrirGrafico(colunas,data,tempoCol,nomeArquivo)

    n = numel(colunas);
    t = data{:,tempoCol};

    figure('Name','Gráficos Estáticos',...
        'Position',[600 200 650 250*n]);

    cores = lines(n);
    
    % Obter ajustes de zero para este arquivo
    ajustes = obterAjustesZero(nomeArquivo);
    
    for i = 1:n
        subplot(n,1,i)

        nomeCol = colunas{i};
        x_bruto = data.(nomeCol);
        x_tratado = tratarSinalButterworth(x_bruto, t);

        % DEBUG: Mostrar nome da coluna e seus bytes
        % disp(['📌 Coluna: "' nomeCol '" | Bytes: ' num2str(double(nomeCol))]);

        % Compensação de atraso (em número de amostras)
        atraso_amostras = round(0.013 * 180);  % 180 Hz = taxa de amostragem
        
        if atraso_amostras > 0 && atraso_amostras < length(x_tratado)
            % Desloca o sinal tratado para frente
            x_tratado = [x_tratado(atraso_amostras+1:end); repmat(x_tratado(end), atraso_amostras, 1)];
        end

        % Aplicar ajuste de zero se existir para esta coluna
        ajuste_valor = buscarAjuste(nomeCol, ajustes);
        
        if ajuste_valor ~= 0
            % disp(['✏️  Aplicando ajuste em "' nomeCol '": ' num2str(ajuste_valor)]);
            x_tratado = x_tratado + ajuste_valor;
        % else
        %     disp(['ℹ️  Sem ajuste para "' nomeCol '"']);
        end

        % Descomente se quiser ver o sinal bruto
        plot(t, x_bruto,'Color',[0.8 0.8 0.8],'LineWidth',0.8); hold on

        plot(t, x_tratado,...
            'LineWidth',1.6,...
            'Color',cores(i,:))

        grid on
        xlabel('Tempo (s)')
        ylabel(nomeCol)
        title(nomeCol)
    end
end

%% -------- APLICAR AJUSTE BASEADO EM PREFIXO --------
function ajuste = buscarAjuste(nomeColuna, ajustes)
    % Busca ajuste comparando apenas o prefixo (antes do parêntese)
    ajuste = 0;  % Padrão: sem ajuste
    
    % Extrair prefixo da coluna (tudo antes do '(')
    idx = strfind(nomeColuna, '(');
    if ~isempty(idx)
        prefixo = strtrim(nomeColuna(1:idx(1)-1));
    else
        prefixo = nomeColuna;
    end
    
    % Verificar se existe ajuste para este prefixo
    if isfield(ajustes, prefixo)
        ajuste = ajustes.(prefixo);
    end
end

%% -------- TRATAMENTO COM FILTRO BUTTERWORTH --------
function x_clean = tratarSinalButterworth(x, tempo)
    % ========== CONFIGURAÇÕES DO FILTRO ==========
    fs_original = 180;           % Frequência de amostragem (Hz)
    fc = 3;                     % Frequência de corte (Hz) 50
    ordem = 6;                   % Ordem do filtro 6
    fator_interpolacao = 1;      % DESATIVADO para evitar defasagem 
    janela_mediana = 5;          % Janela para remover picos
    
    % ========== PROCESSAMENTO ==========
    x = x(:);  % Garante vetor coluna
    
    % PASSO 0: Remover NaN e Inf
    idx_validos = isfinite(x);
    
    if sum(idx_validos) < length(x) * 0.5
        warning('Mais de 50% dos dados são inválidos. Retornando sinal original.');
        x_clean = x;
        return;
    end
    
    % Interpolar valores inválidos se houver poucos
    if any(~idx_validos)
        x_limpo = x;
        indices = 1:length(x);
        x_limpo(~idx_validos) = interp1(indices(idx_validos), x(idx_validos), ...
                                         indices(~idx_validos), 'linear', 'extrap');
        x = x_limpo;
    end
    
    % PASSO 1: Remover picos espúrios (outliers)
    x_sem_picos = medfilt1(x, janela_mediana);
    
    % PASSO 2: Interpolação (aumenta resolução)
    if fator_interpolacao > 1
        fs_nova = fs_original * fator_interpolacao;
        
        % Validar dados antes de interpolar
        idx_validos = isfinite(x_sem_picos) & isfinite(tempo);
        
        if sum(idx_validos) < 2
            warning('Dados insuficientes. Usando sinal sem interpolação.');
            fs_nova = fs_original;
            x_interpolado = x_sem_picos;
        else
            tempo_valido = tempo(idx_validos);
            x_valido = x_sem_picos(idx_validos);
            
            % CORREÇÃO: Remover valores duplicados de tempo
            [tempo_unico, idx_unicos] = unique(tempo_valido, 'stable');
            x_unico = x_valido(idx_unicos);
            
            % Verificar se ainda temos dados suficientes
            if length(tempo_unico) < 2
                warning('Pontos únicos insuficientes. Usando sinal sem interpolação.');
                fs_nova = fs_original;
                x_interpolado = x_sem_picos;
                fator_interpolacao = 1;
            else
                % Criar tempo interpolado
                tempo_novo = linspace(tempo_unico(1), tempo_unico(end), ...
                                      length(tempo_unico) * fator_interpolacao)';
                
                % Interpolação LINEAR para dados digitais (não spline!)
                x_interpolado = interp1(tempo_unico, x_unico, tempo_novo, 'linear');
                
                % Verificar resultado
                if any(~isfinite(x_interpolado))
                    warning('Interpolação gerou NaN/Inf. Usando sinal original.');
                    fs_nova = fs_original;
                    x_interpolado = x_sem_picos;
                    fator_interpolacao = 1; % Desativa downsampling
                end
            end
        end
    else
        fs_nova = fs_original;
        x_interpolado = x_sem_picos;
    end
    
    % PASSO 3: Filtro Butterworth passa-baixa
    [b, a] = butter(ordem, fc/(fs_nova/2), 'low');
    x_filtrado = filtfilt(b, a, x_interpolado);
    
    % PASSO 4: Retornar na frequência original (downsampling)
    if fator_interpolacao > 1
        x_clean = x_filtrado(1:fator_interpolacao:end);
    else
        x_clean = x_filtrado;
    end
    
    % Garantir mesmo tamanho do sinal original
    if length(x_clean) > length(x)
        x_clean = x_clean(1:length(x));
    elseif length(x_clean) < length(x)
        % Preencher com último valor se necessário
        x_clean = [x_clean; repmat(x_clean(end), length(x) - length(x_clean), 1)];
    end
end