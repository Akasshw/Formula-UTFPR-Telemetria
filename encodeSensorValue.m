function encoded = encodeSensorValue(value)

    value = uint16(value);
    binStr = dec2bin(value);

    remainder = mod(length(binStr),6);
    if remainder ~= 0
        pad = 6 - remainder;
        binStr = [repmat('0',1,pad) binStr];
    end

    numBlocks = length(binStr)/6;
    encoded = '';

    for i = 1:numBlocks
        block = binStr((i-1)*6+1:i*6);
        decimalValue = bin2dec(block);
        decimalValue = decimalValue + 32;
        encoded = [encoded char(decimalValue)];
    end
end