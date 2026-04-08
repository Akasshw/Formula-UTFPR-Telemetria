clear
clc

%% ===== MQTT CONFIG =====
brokerAddress = "tcp://mrrpformula.ddns.net";
port          = 1883;
client        = mqttclient(brokerAddress, Port=port, Username="client", Password="client_futfpr");
disp("Sender iniciado...")

%% ===== MAPEAMENTO DE SENSORES =====
% "A":"rpm", "B":"steering_angle", "C":"oil_temp", "D":"speed",
% "E":"throttle", "F":"brake", "G":"gear", "H":"water_temp",
% "I":"voltage", "J":"fuel_level"
sensorIDs = {'A','B','C','D','E','F','G','H','I','J'};

%% ===== LOOP DE ENVIO =====
t0 = tic;
while true
    tempo = toc(t0);

    % Simula cada sensor com ondas distintas
    rpm        = round(4000 + 1500 * sin(2*pi*0.5*tempo));
    steering   = round(20   * sin(2*pi*0.2*tempo));
    oil_temp   = round(90   + 10  * sin(2*pi*0.05*tempo));
    speed      = round(80   + 40  * sin(2*pi*0.3*tempo));
    throttle   = round(50   + 45  * sin(2*pi*0.4*tempo));
    brake      = round(max(0, 30  * sin(2*pi*0.35*tempo + pi)));
    gear       = min(6, max(1, round(1 + 5*(0.5 + 0.5*sin(2*pi*0.1*tempo)))));
    water_temp = round(85   + 8   * sin(2*pi*0.07*tempo));
    voltage    = round(12   + 1   * sin(2*pi*0.03*tempo));
    fuel_level = round(max(0, 100 - 0.5*tempo));

    values = {rpm, steering, oil_temp, speed, throttle, ...
              brake, gear, water_temp, voltage, fuel_level};

    % ---- TIMESTAMP ----
    % Manda o tempo Unix atual como prefixo: "T~1712345678.123|A~DADO..."
    % O receiver usa esse timestamp para plotar corretamente mesmo se houver atraso
    unixNow = posixtime(datetime('now','TimeZone','UTC'));
    msg = sprintf('T~%.3f|', unixNow);

    % Monta o restante da mensagem: A~DADOB~DADOC~DADO...
    for i = 1:length(sensorIDs)
        encoded = encodeSensorValue(values{i});
        msg = [msg sensorIDs{i} '~' encoded '|'];
    end

    write(client, "sensors", msg);
    fprintf('Enviado [%.1fs]: rpm=%d  speed=%d  throttle=%d  gear=%d\n', ...
            tempo, rpm, speed, throttle, gear);

    pause(0.05); % 20 Hz
end

%% ===== FUNCAO DE ENCODE =====
function encoded = encodeSensorValue(value)
    value    = uint16(value);
    binStr   = dec2bin(value);
    remainder = mod(length(binStr), 6);
    if remainder ~= 0
        binStr = [repmat('0', 1, 6-remainder) binStr];
    end
    numBlocks = length(binStr) / 6;
    encoded   = '';
    for i = 1:numBlocks
        block        = binStr((i-1)*6+1 : i*6);
        decimalValue = bin2dec(block) + 32;
        encoded      = [encoded char(decimalValue)];
    end
end