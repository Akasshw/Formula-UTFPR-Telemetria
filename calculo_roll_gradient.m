clear; clc; close all;

% ================== ANÁLISE DE ROLL GRADIENT ==================
% Este script processa dados TRATADOS de telemetria e calcula o Roll Gradient
% Autor: Fórmula UTFPR
% ================================================================

disp('========================================');
disp('   ANÁLISE DE ROLL GRADIENT');
disp('========================================');
disp(' ');
disp('Selecione o arquivo CSV com dados TRATADOS...');

% -------- SELEÇÃO DO ARQUIVO --------
[arquivo, caminho] = uigetfile('*.csv', 'Selecione o arquivo CSV com dados tratados');

if isequal(arquivo, 0)
    disp('❌ Nenhum arquivo selecionado');
    return
end

arquivoCompleto = fullfile(caminho, arquivo);
disp(['📂 Lendo: ' arquivo]);

[~, nomeArquivo, ~] = fileparts(arquivo);

try
    data = readtable(arquivoCompleto, 'VariableNamingRule', 'preserve');
catch ME
    disp('❌ Erro ao ler arquivo CSV');
    disp(ME.message);
    return
end

disp(['✅ Arquivo carregado: ' num2str(height(data)) ' linhas, ' num2str(width(data)) ' colunas']);
disp(' ');

% -------- PARÂMETROS DO VEÍCULO --------
params = struct();
params.L_bracoSuspensao = 25;  % mm - Raio do braço (centro do pivô ao ponto de medição do sensor)
params.Tf = 1190;              % mm - Front track width
params.Tr = 1164;              % mm - Rear track width  
params.MRf = 2.44;             % Motion Ratio dianteiro (MR = 1/Install_Ratio, não confundir!)
params.MRr = 2.37;             % Motion Ratio traseiro (MR = 1/Install_Ratio, não confundir!)

% Criar interface para ajustar parâmetros
abrirInterfaceParametros(data, nomeArquivo, params, arquivoCompleto);

%% ========== INTERFACE DE PARÂMETROS ==========
function abrirInterfaceParametros(data, nomeArquivo, params, arquivoCompleto)
    
    dlg = uifigure('Name','Parâmetros do Veículo','Position',[500 250 400 400]);

    uilabel(dlg,'Text','CONFIGURAÇÃO DO VEÍCULO',...
        'Position',[50 360 300 25],'FontWeight','bold','FontSize',14,...
        'HorizontalAlignment','center');
    
    % Aviso sobre Motion Ratio
    uilabel(dlg,'Text','⚠️ Motion Ratio = 1 / Install Ratio',...
        'Position',[50 340 300 15],'FontSize',9,...
        'HorizontalAlignment','center','FontColor',[0.8 0.2 0.1]);

    % Comprimento do braço
    uilabel(dlg,'Text','Comprimento do Braço L (mm):',...
        'Position',[30 320 220 20]);
    edt_L = uieditfield(dlg,'numeric','Position',[260 320 110 22],...
        'Value',params.L_bracoSuspensao);

    % Track width dianteira
    uilabel(dlg,'Text','Track Width Dianteira Tf (mm):',...
        'Position',[30 280 220 20]);
    edt_Tf = uieditfield(dlg,'numeric','Position',[260 280 110 22],...
        'Value',params.Tf);

    % Track width traseira
    uilabel(dlg,'Text','Track Width Traseira Tr (mm):',...
        'Position',[30 240 220 20]);
    edt_Tr = uieditfield(dlg,'numeric','Position',[260 240 110 22],...
        'Value',params.Tr);

    % Motion ratio dianteiro
    uilabel(dlg,'Text','Motion Ratio Dianteiro MRf:',...
        'Position',[30 200 220 20]);
    edt_MRf = uieditfield(dlg,'numeric','Position',[260 200 110 22],...
        'Value',params.MRf);

    % Motion ratio traseiro
    uilabel(dlg,'Text','Motion Ratio Traseiro MRr:',...
        'Position',[30 160 220 20]);
    edt_MRr = uieditfield(dlg,'numeric','Position',[260 160 110 22],...
        'Value',params.MRr);

    % Separador
    uilabel(dlg,'Text','_________________________________',...
        'Position',[30 130 340 20],'HorizontalAlignment','center');

    % Botões
    uibutton(dlg,'Text','📊 Calcular e Plotar',...
        'Position',[60 70 280 45],...
        'FontSize',13,...
        'FontWeight','bold',...
        'ButtonPushedFcn',@(btn,event) executarCalculo());

    uibutton(dlg,'Text','❌ Cancelar',...
        'Position',[60 20 280 35],...
        'ButtonPushedFcn',@(btn,event) close(dlg));

    % -------- FUNÇÃO DE CÁLCULO (NESTED FUNCTION) --------
    function executarCalculo()
        % Atualizar parâmetros
        params.L_bracoSuspensao = edt_L.Value;
        params.Tf = edt_Tf.Value;
        params.Tr = edt_Tr.Value;
        params.MRf = edt_MRf.Value;
        params.MRr = edt_MRr.Value;
        
        close(dlg);
        
        disp('========================================');
        disp('PARÂMETROS CONFIGURADOS:');
        disp(['  L (braço): ' num2str(params.L_bracoSuspensao) ' mm']);
        disp(['  Tf (track front): ' num2str(params.Tf) ' mm']);
        disp(['  Tr (track rear): ' num2str(params.Tr) ' mm']);
        disp(['  MRf: ' num2str(params.MRf)]);
        disp(['  MRr: ' num2str(params.MRr)]);
        disp('========================================');
        disp(' ');
        
        % Processar dados
        processarRollGradient(data, nomeArquivo, params, arquivoCompleto);
    end
end

%% ========== FUNÇÃO PRINCIPAL DE PROCESSAMENTO ==========
function processarRollGradient(data, nomeArquivo, params, arquivoCompleto)
    
    colNames = data.Properties.VariableNames;
    
    % -------- IDENTIFICAR COLUNAS --------
    disp('🔍 Buscando colunas necessárias...');
    
    % Coluna de tempo (geralmente a última)
    idx_tempo = find(contains(colNames, 'time', 'IgnoreCase', true) | ...
                     contains(colNames, 'tempo', 'IgnoreCase', true), 1, 'last');
    
    if isempty(idx_tempo)
        idx_tempo = length(colNames);  % Assume última coluna
    end
    
    % Colunas de suspensão
    idx_FL = find(contains(colNames, 'Susp_Pos_FL', 'IgnoreCase', true), 1);
    idx_FR = find(contains(colNames, 'Susp_Pos_FR', 'IgnoreCase', true), 1);
    idx_RL = find(contains(colNames, 'Susp_Pos_RL', 'IgnoreCase', true), 1);
    idx_RR = find(contains(colNames, 'Susp_Pos_RR', 'IgnoreCase', true), 1);
    
    % Coluna de aceleração lateral
    idx_Glat = find(contains(colNames, 'G_lat', 'IgnoreCase', true) | ...
                    contains(colNames, 'Lateral', 'IgnoreCase', true) | ...
                    contains(colNames, 'Glat', 'IgnoreCase', true) | ...
                    contains(colNames, 'Accel_X', 'IgnoreCase', true) | ...
                    contains(colNames, 'AccelX', 'IgnoreCase', true), 1);
    
    % -------- VALIDAÇÃO --------
    if isempty(idx_FL) || isempty(idx_FR) || isempty(idx_RL) || isempty(idx_RR)
        errordlg(['❌ Colunas de suspensão não encontradas!' newline newline ...
                  'Certifique-se que o arquivo contém:' newline ...
                  '  • Susp_Pos_FL' newline ...
                  '  • Susp_Pos_FR' newline ...
                  '  • Susp_Pos_RL' newline ...
                  '  • Susp_Pos_RR'], 'Erro');
        return;
    end
    
    disp(['✅ Coluna FL: ' colNames{idx_FL}]);
    disp(['✅ Coluna FR: ' colNames{idx_FR}]);
    disp(['✅ Coluna RL: ' colNames{idx_RL}]);
    disp(['✅ Coluna RR: ' colNames{idx_RR}]);
    disp(['✅ Coluna Tempo: ' colNames{idx_tempo}]);
    
    if isempty(idx_Glat)
        disp('⚠️  Coluna de aceleração lateral não encontrada');
        disp('   O código procurou por: G_lat, Lateral, Glat, Accel_Y, AccelY');
        disp('   Colunas disponíveis no arquivo:');
        for i = 1:min(10, length(colNames))
            disp(['      - ' colNames{i}]);
        end
        if length(colNames) > 10
            disp(['      ... e mais ' num2str(length(colNames)-10) ' colunas']);
        end
        disp(' ');
        disp('   ⚠️  SEM ACELERAÇÃO LATERAL: Roll Gradient NÃO será calculado');
        disp('   Apenas ângulo de rolagem e cursos serão plotados.');
        disp(' ');
        tem_glat = false;
    else
        disp(['✅ Coluna Aceleração Lateral: ' colNames{idx_Glat}]);
        tem_glat = true;
    end
    
    disp(' ');
    
    % -------- EXTRAIR DADOS --------
    t = data{:, idx_tempo};
    
    % Dados de suspensão JÁ TRATADOS (em graus)
    x_FL_deg = data{:, idx_FL};
    x_FR_deg = data{:, idx_FR};
    x_RL_deg = data{:, idx_RL};
    x_RR_deg = data{:, idx_RR};
    
    disp('📐 Convertendo dados de graus para mm...');
    
    % -------- CONVERSÃO: GRAUS → MM --------
    % Fórmula: x_mm = L × θ_radianos = L × (θ_graus × π/180)
    x_FL_mm = params.L_bracoSuspensao * (x_FL_deg * pi/180);
    x_FR_mm = params.L_bracoSuspensao * (x_FR_deg * pi/180);
    x_RL_mm = params.L_bracoSuspensao * (x_RL_deg * pi/180);
    x_RR_mm = params.L_bracoSuspensao * (x_RR_deg * pi/180);
    
    disp('✅ Conversão concluída');
    disp(' ');
    
    % -------- CÁLCULO DO ÂNGULO DE ROLAGEM (Eq. 9.6) --------
    disp('🧮 Calculando ângulo de rolagem...');
    
    % α_roll = arctan( ((x_FL - x_FR)·MR_f - (x_RL - x_RR)·MR_r) / (T_f - T_r) ) × 57.3
    
    numerador = (x_FR_mm - x_FL_mm) * params.MRf + (x_RL_mm - x_RR_mm) * params.MRr;
    denominador = (params.Tf + params.Tr);
    
    % Tratamento especial se track widths forem iguais
    if abs(denominador) < 0.001
        disp('⚠️  Track widths iguais - usando apenas Tf');
        denominador = params.Tf;
    end
    
    alpha_roll_rad = atan(numerador / denominador);
    alpha_roll_deg = alpha_roll_rad * 57.3;  % Converter para graus
    
    disp(['✅ Ângulo de rolagem calculado (máx: ' num2str(max(abs(alpha_roll_deg)), '%.2f') '°)']);
    disp(' ');
    
    % -------- CÁLCULO DO ROLL GRADIENT (Eq. 9.3) --------
    if tem_glat
        disp('🧮 Calculando Roll Gradient...');
        
        G_lat = data{:, idx_Glat};
        
        % RG = α_roll / G_lat
        RG = zeros(size(alpha_roll_deg));
        idx_valido = abs(G_lat) > 0.01;  % Considerar apenas |G_lat| > 0.01g
        RG(idx_valido) = alpha_roll_deg(idx_valido) ./ G_lat(idx_valido);
        
        % Estatísticas
        RG_medio = mean(RG(idx_valido));
        RG_std = std(RG(idx_valido));
        
        disp(['✅ Roll Gradient médio: ' num2str(RG_medio, '%.2f') ' °/g']);
        disp(['   Desvio padrão: ' num2str(RG_std, '%.2f') ' °/g']);
        disp(' ');
        
        % -------- PLOTAGEM COMPLETA --------
        plotarResultadosCompletos(t, x_FL_mm, x_FR_mm, x_RL_mm, x_RR_mm, ...
                                  alpha_roll_deg, G_lat, RG, idx_valido, ...
                                  params, nomeArquivo);
        
        % -------- SALVAR RESULTADOS --------
        salvarResultadosRG(nomeArquivo, t, alpha_roll_deg, G_lat, RG, params, arquivoCompleto);
        
    else
        % Plotagem sem G_lat
        plotarResultadosSemGlat(t, x_FL_mm, x_FR_mm, x_RL_mm, x_RR_mm, ...
                                alpha_roll_deg, params, nomeArquivo);
    end
    
    disp('✅ Análise concluída!');
end

%% ========== PLOTAGEM COMPLETA (COM G_LAT) ==========
function plotarResultadosCompletos(t, x_FL, x_FR, x_RL, x_RR, alpha_roll, G_lat, RG, idx_valido, params, nomeArquivo)
    
    % Cores do tema escuro profissional
    cor_fundo = [0.15 0.15 0.18];
    cor_grid = [0.3 0.3 0.35];
    cor_texto = [0.9 0.9 0.92];
    
    figure('Name','Roll Gradient Analysis - Fórmula UTFPR',...
           'Position',[50 50 1600 900],...
           'Color',cor_fundo);
    
    % -------- SUBPLOT 1: Cursos de Suspensão --------
    ax1 = subplot(2,3,1);
    plot(t, x_FL, 'LineWidth', 2, 'Color', [0.3 0.7 1.0], 'DisplayName', 'FL')
    hold on
    plot(t, x_FR, 'LineWidth', 2, 'Color', [1.0 0.4 0.3], 'DisplayName', 'FR')
    plot(t, x_RL, 'LineWidth', 2, 'Color', [0.4 1.0 0.4], 'DisplayName', 'RL')
    plot(t, x_RR, 'LineWidth', 2, 'Color', [1.0 0.8 0.2], 'DisplayName', 'RR')
    
    set(ax1, 'Color', cor_fundo, 'XColor', cor_texto, 'YColor', cor_texto, 'GridColor', cor_grid)
    grid on
    xlabel('Tempo (s)', 'FontSize', 11, 'Color', cor_texto)
    ylabel('Curso (mm)', 'FontSize', 11, 'Color', cor_texto)
    title('Cursos de Suspensão', 'FontSize', 12, 'FontWeight', 'bold', 'Color', cor_texto)
    legend('Location', 'best', 'TextColor', cor_texto, 'Color', [0.2 0.2 0.23])
    
    % -------- SUBPLOT 2: Ângulo de Rolagem vs Tempo --------
    ax2 = subplot(2,3,2);
    plot(t, alpha_roll, 'LineWidth', 2.5, 'Color', [0.3 0.7 1.0])
    yline(0, '--', 'LineWidth', 1.5, 'Color', [0.6 0.6 0.65])
    
    set(ax2, 'Color', cor_fundo, 'XColor', cor_texto, 'YColor', cor_texto, 'GridColor', cor_grid)
    grid on
    xlabel('Tempo (s)', 'FontSize', 11, 'Color', cor_texto)
    ylabel('Ângulo de Rolagem (°)', 'FontSize', 11, 'Color', cor_texto)
    title('Ângulo de Rolagem vs Tempo', 'FontSize', 12, 'FontWeight', 'bold', 'Color', cor_texto)
    
    % -------- SUBPLOT 3: Aceleração Lateral vs Tempo --------
    ax3 = subplot(2,3,3);
    plot(t, G_lat, 'LineWidth', 2.5, 'Color', [1.0 0.5 0.2])
    yline(0, '--', 'LineWidth', 1.5, 'Color', [0.6 0.6 0.65])
    
    set(ax3, 'Color', cor_fundo, 'XColor', cor_texto, 'YColor', cor_texto, 'GridColor', cor_grid)
    grid on
    xlabel('Tempo (s)', 'FontSize', 11, 'Color', cor_texto)
    ylabel('Aceleração Lateral (g)', 'FontSize', 11, 'Color', cor_texto)
    title('Aceleração Lateral vs Tempo', 'FontSize', 12, 'FontWeight', 'bold', 'Color', cor_texto)
    
    % -------- SUBPLOT 4-5: GRÁFICO PRINCIPAL - Roll Angle vs G_lat --------
    ax4 = subplot(2,3,[4 5]);
    scatter(G_lat(idx_valido), alpha_roll(idx_valido), 35, [0.4 0.8 1.0], 'filled', ...
            'MarkerFaceAlpha', 0.6)
    hold on
    
    % Linha de tendência
    p_angle = polyfit(G_lat(idx_valido), alpha_roll(idx_valido), 1);
    G_fit = linspace(min(G_lat(idx_valido)), max(G_lat(idx_valido)), 100);
    plot(G_fit, polyval(p_angle, G_fit), '-', 'LineWidth', 4, 'Color', [1.0 0.3 0.3])
    
    % Calcular R²
    R2_angle = 1 - sum((alpha_roll(idx_valido) - polyval(p_angle, G_lat(idx_valido))).^2) / ...
                   sum((alpha_roll(idx_valido) - mean(alpha_roll(idx_valido))).^2);
    
    set(ax4, 'Color', cor_fundo, 'XColor', cor_texto, 'YColor', cor_texto, 'GridColor', cor_grid)
    grid on
    xlabel('Aceleração Lateral (g)', 'FontSize', 13, 'FontWeight', 'bold', 'Color', cor_texto)
    ylabel('Roll Angle (°)', 'FontSize', 13, 'FontWeight', 'bold', 'Color', cor_texto)
    title('🎯 ROLL ANGLE vs ACELERAÇÃO LATERAL', 'FontSize', 14, 'FontWeight', 'bold', 'Color', [1.0 0.8 0.2])
    
    % Legend melhorada
    leg = legend({sprintf('Dados (n=%d)', sum(idx_valido)), ...
                  sprintf('Roll Gradient = %.2f °/g  |  R² = %.4f', p_angle(1), R2_angle)}, ...
                 'Location', 'northwest', 'FontSize', 11);
    set(leg, 'TextColor', cor_texto, 'Color', [0.2 0.2 0.23], 'EdgeColor', [0.5 0.5 0.55])
    
    % -------- SUBPLOT 6: Painel de Estatísticas MELHORADO --------
    ax6 = subplot(2,3,6);
    axis off
    
    alpha_max = max(abs(alpha_roll));
    glat_max = max(abs(G_lat));
    RG_medio = mean(RG(idx_valido));
    RG_std = std(RG(idx_valido));
    
    % Criar painel visual moderno
    annotation('rectangle', [0.685 0.08 0.29 0.38], ...
               'FaceColor', [0.18 0.18 0.22], ...
               'EdgeColor', [0.4 0.6 1.0], ...
               'LineWidth', 2);
    
    % Título do painel
    annotation('textbox', [0.72 0.40 0.2 0.05], ...
               'String', '📊 ESTATÍSTICAS', ...
               'FontSize', 14, 'FontWeight', 'bold', ...
               'Color', [1.0 0.8 0.2], ...
               'HorizontalAlignment', 'center', ...
               'EdgeColor', 'none', ...
               'BackgroundColor', 'none');
    
    % Separador
    annotation('line', [0.70 0.96], [0.395 0.395], ...
               'Color', [0.4 0.6 1.0], 'LineWidth', 1.5);
    
    % ROLL GRADIENT (destaque principal)
    annotation('textbox', [0.70 0.33 0.24 0.06], ...
               'String', sprintf('🎯 ROLL GRADIENT\n%.2f °/g', p_angle(1)), ...
               'FontSize', 16, 'FontWeight', 'bold', ...
               'Color', [0.3 1.0 0.4], ...
               'HorizontalAlignment', 'center', ...
               'EdgeColor', [0.3 1.0 0.4], ...
               'LineWidth', 2, ...
               'BackgroundColor', [0.1 0.15 0.12]);
    
    % R²
    annotation('textbox', [0.70 0.26 0.24 0.04], ...
               'String', sprintf('R² = %.4f', R2_angle), ...
               'FontSize', 12, 'FontWeight', 'bold', ...
               'Color', [0.4 0.8 1.0], ...
               'HorizontalAlignment', 'center', ...
               'EdgeColor', 'none', ...
               'BackgroundColor', 'none');
    
    % Separador
    annotation('line', [0.70 0.96], [0.255 0.255], ...
               'Color', [0.4 0.4 0.45], 'LineWidth', 1);
    
    % Outras estatísticas
    stats_text = sprintf(['α Roll Máx:  %.2f°\n' ...
                         'G_lat Máx:   %.2f g\n' ...
                         'RG Médio:    %.2f °/g\n' ...
                         'Desvio Pad:  %.2f °/g'], ...
                         alpha_max, glat_max, RG_medio, RG_std);
    
    annotation('textbox', [0.70 0.16 0.24 0.09], ...
               'String', stats_text, ...
               'FontSize', 10, ...
               'Color', [0.85 0.85 0.88], ...
               'HorizontalAlignment', 'left', ...
               'EdgeColor', 'none', ...
               'BackgroundColor', 'none', ...
               'FontName', 'Consolas');
    
    % Separador
    annotation('line', [0.70 0.96], [0.155 0.155], ...
               'Color', [0.4 0.4 0.45], 'LineWidth', 1);
    
    % Parâmetros do veículo
    params_text = sprintf(['PARÂMETROS\n' ...
                          'L:    %.1f mm\n' ...
                          'Tf:   %.0f mm\n' ...
                          'Tr:   %.0f mm\n' ...
                          'MRf:  %.2f\n' ...
                          'MRr:  %.2f'], ...
                          params.L_bracoSuspensao, params.Tf, params.Tr, ...
                          params.MRf, params.MRr);
    
    annotation('textbox', [0.70 0.08 0.24 0.075], ...
               'String', params_text, ...
               'FontSize', 9, ...
               'Color', [0.7 0.7 0.73], ...
               'HorizontalAlignment', 'left', ...
               'EdgeColor', 'none', ...
               'BackgroundColor', 'none', ...
               'FontName', 'Consolas');
    
    % Título geral da figura
    sgtitle(['Roll Gradient Analysis - ' nomeArquivo], ...
            'FontSize', 16, 'FontWeight', 'bold', 'Color', cor_texto, 'Interpreter', 'none')
end

%% ========== PLOTAGEM SEM G_LAT ==========
function plotarResultadosSemGlat(t, x_FL, x_FR, x_RL, x_RR, alpha_roll, params, nomeArquivo)
    
    figure('Name','Análise de Ângulo de Rolagem - Fórmula UTFPR',...
           'Position',[100 100 1200 700],...
           'Color','w');
    
    % Subplot 1: Cursos
    subplot(2,2,1)
    plot(t, x_FL, 'LineWidth', 1.8, 'DisplayName', 'FL')
    hold on
    plot(t, x_FR, 'LineWidth', 1.8, 'DisplayName', 'FR')
    plot(t, x_RL, 'LineWidth', 1.8, 'DisplayName', 'RL')
    plot(t, x_RR, 'LineWidth', 1.8, 'DisplayName', 'RR')
    grid on
    xlabel('Tempo (s)')
    ylabel('Curso (mm)')
    title('Cursos de Suspensão', 'FontWeight', 'bold')
    legend('Location', 'best')
    
    % Subplot 2: Ângulo de rolagem
    subplot(2,2,[2 4])
    plot(t, alpha_roll, 'LineWidth', 2.5, 'Color', [0.3 0.6 0.9])
    grid on
    xlabel('Tempo (s)', 'FontSize', 11, 'FontWeight', 'bold')
    ylabel('Ângulo de Rolagem (°)', 'FontSize', 11, 'FontWeight', 'bold')
    title('🎯 ÂNGULO DE ROLAGEM DO VEÍCULO', 'FontSize', 13, 'FontWeight', 'bold')
    yline(0, 'k--', 'LineWidth', 1.5)
    
    % Subplot 3: Info
    subplot(2,2,3)
    axis off
    
    alpha_max = max(abs(alpha_roll));
    alpha_mean = mean(alpha_roll);
    
    texto = sprintf(['╔════════════════════════════╗\n' ...
                    '║   ESTATÍSTICAS             ║\n' ...
                    '╠════════════════════════════╣\n' ...
                    '║ α Roll Máx:  %6.2f °     ║\n' ...
                    '║ α Roll Méd:  %6.2f °     ║\n' ...
                    '╠════════════════════════════╣\n' ...
                    '║   PARÂMETROS               ║\n' ...
                    '╠════════════════════════════╣\n' ...
                    '║ L braço:     %6.1f mm    ║\n' ...
                    '║ Track F:     %6.0f mm    ║\n' ...
                    '║ Track R:     %6.0f mm    ║\n' ...
                    '║ MR Front:    %6.2f       ║\n' ...
                    '║ MR Rear:     %6.2f       ║\n' ...
                    '╚════════════════════════════╝\n\n' ...
                    '⚠️  Aceleração lateral não encontrada'], ...
                    alpha_max, alpha_mean, ...
                    params.L_bracoSuspensao, params.Tf, params.Tr, ...
                    params.MRf, params.MRr);
    
    text(0.05, 0.5, texto, 'FontSize', 10, 'VerticalAlignment', 'middle', ...
        'FontName', 'Courier New', 'BackgroundColor', [0.95 0.95 0.98], ...
        'EdgeColor', [0.3 0.3 0.5], 'LineWidth', 1.5, 'Margin', 8)
    
    sgtitle(['Roll Angle Analysis - ' nomeArquivo], ...
            'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none')
end

%% ========== SALVAR RESULTADOS ==========
function salvarResultadosRG(nomeArquivo, t, alpha_roll, G_lat, RG, params, arquivoOriginal)
    
    % Criar tabela com resultados
    resultados = table(t, alpha_roll, G_lat, RG, ...
        'VariableNames', {'Tempo_s', 'AnguloRolagem_deg', 'AceleracaoLateral_g', 'RollGradient_degPorg'});
    
    % Determinar caminho de saída (mesma pasta do arquivo original)
    [caminho_original, ~, ~] = fileparts(arquivoOriginal);
    arquivo_saida = fullfile(caminho_original, [nomeArquivo '_RollGradient.csv']);
    
    % Salvar CSV
    try
        writetable(resultados, arquivo_saida);
        disp(' ');
        disp('========================================');
        disp('💾 RESULTADOS SALVOS');
        disp('========================================');
        disp(['📁 Arquivo: ' arquivo_saida]);
        disp(['📊 Linhas: ' num2str(height(resultados))]);
        
        % Calcular e mostrar estatísticas
        idx_valido = abs(G_lat) > 0.01;
        RG_medio = mean(RG(idx_valido));
        RG_std = std(RG(idx_valido));
        
        disp(['📈 RG Médio: ' num2str(RG_medio, '%.2f') ' °/g']);
        disp(['📊 Desvio Padrão: ' num2str(RG_std, '%.2f') ' °/g']);
        disp('========================================');
        
    catch ME
        disp(['❌ Erro ao salvar: ' ME.message]);
    end
end