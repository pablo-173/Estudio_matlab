%% ANALISIS EOG - ELIMINACION DE SEGMENTOS NO DESEADOS (BIOPAC / AcqKnowledge)
% Flujo: cargar -> filtrar -> marcar segmentos -> eliminar -> graficar -> guardar
% Requiere: Signal Processing Toolbox (butter, filtfilt, iirnotch)
clear; clc; close all;

%% 1. CONFIGURACION (lo unico que normalmente hay que editar)
archivo   = 'EOG17.mat';   % .mat exportado desde AcqKnowledge (ver nota abajo)
canal_eog = 1;                    % indice del canal EOG dentro del archivo

% Segmentos a eliminar, en segundos: [inicio fin]. Una fila por segmento.
% Dejalo vacio ([]) si quieres marcarlos a mano con el mouse.
segmentos_eliminar = [];
                        % ej: inicio con ruido/calibracion
                       
                       

modo = 'recortar';   % 'recortar' = quita los segmentos y une el resto
                     % 'nan'      = conserva el eje de tiempo y pone NaN



%% 2. CARGAR DATOS
[senal, fs, etiqueta, unidad] = cargar_biopac(archivo, canal_eog);
N = numel(senal);
t = (0:N-1)' / fs;
fprintf('Canal: %s | fs = %.1f Hz | duracion = %.2f s\n', etiqueta, fs, t(end));
senal_f = senal;



%% 4. SELECCION DE SEGMENTOS
if isempty(segmentos_eliminar)
    segmentos_eliminar = seleccionar_interactivo(t, senal_f, unidad);
end

% Validacion
segmentos_eliminar = sort(segmentos_eliminar, 2);          % inicio < fin
segmentos_eliminar = max(min(segmentos_eliminar, t(end)), 0); % dentro del rango

%% 5. ELIMINAR SEGMENTOS
conservar = true(N, 1);
for k = 1:size(segmentos_eliminar, 1)
    conservar(t >= segmentos_eliminar(k,1) & t <= segmentos_eliminar(k,2)) = false;
end

switch lower(modo)
    case 'recortar'
        senal_limpia = senal_f(conservar);
        t_original   = t(conservar);                 % tiempos originales conservados
        t_limpia     = (0:numel(senal_limpia)-1)' / fs;  % eje continuo nuevo
    case 'nan'
        senal_limpia = senal_f;
        senal_limpia(~conservar) = NaN;
        t_original   = t;
        t_limpia     = t;
    otherwise
        error('modo debe ser ''recortar'' o ''nan''.');
end

fprintf('Eliminado: %.2f s (%.1f %% de la senal)\n', ...
        sum(~conservar)/fs, 100*sum(~conservar)/N);


%% 6. GRAFICAS
figure('Name','EOG','Color','w');

% Señal original con lo eliminado resaltado en rojo
senal_elim = senal;  senal_elim(conservar) = NaN;   % solo lo eliminado
senal_cons = senal;  senal_cons(~conservar) = NaN;  % solo lo conservado

ax1 = subplot(3,1,1); hold on;
plot(t, senal_cons, 'Color', [0 0.447 0.741]);
plot(t, senal_elim, 'r', 'LineWidth', 1.5);
yl = ylim;
for k = 1:size(segmentos_eliminar, 1)
    patch(segmentos_eliminar(k,[1 2 2 1]), yl([1 1 2 2]), 'r', ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none');
    text(mean(segmentos_eliminar(k,:)), yl(2), sprintf('%.1f-%.1f s', ...
        segmentos_eliminar(k,1), segmentos_eliminar(k,2)), ...
        'HorizontalAlignment','center','VerticalAlignment','top','Color','r');
end
xlim([0 t(end)]); grid on;
title('Señal ORIGINAL (rojo = segmentos eliminados)');
ylabel(unidad);

% Señal original sin los segmentos (mismo eje de tiempo original)
ax2 = subplot(3,1,2);
plot(t, senal_cons, 'Color', [0 0.447 0.741]);
xlim([0 t(end)]); grid on;
title('Conservada, en tiempo original (huecos = eliminado)');
ylabel(unidad);
linkaxes([ax1 ax2], 'xy');   % zoom sincronizado

% Resultado final según el modo elegido
subplot(3,1,3);
plot(t_limpia, senal_limpia, 'Color', [0 0.447 0.741]);
grid on;
title(sprintf('Señal LIMPIA (modo: %s)', modo));
xlabel('Tiempo (s)'); ylabel(unidad);

% Resumen en consola
for k = 1:size(segmentos_eliminar, 1)
    fprintf('Segmento %d: %.2f - %.2f s (%.2f s)\n', k, ...
        segmentos_eliminar(k,1), segmentos_eliminar(k,2), ...
        diff(segmentos_eliminar(k,:)));
end

%% 7. GUARDAR
[~, nombre] = fileparts(archivo);
save([nombre '_limpio.mat'], 'senal_limpia', 't_limpia', 'fs', 'segmentos_eliminar', 'modo');
% writematrix([t_limpia senal_limpia], 'eog_limpio.csv');  % opcional

%% ================= FUNCIONES LOCALES =================
function [senal, fs, etiqueta, unidad] = cargar_biopac(archivo, canal)
% Lee un .mat exportado desde AcqKnowledge (File > Save As > MATLAB (*.mat)).
% Variables tipicas: data, isi, isi_units, labels, units
% (Tambien funciona con .mat generados por acq2mat de bioread.)
    [~, ~, ext] = fileparts(archivo);
    if strcmpi(ext, '.acq')
        error(['MATLAB no lee .acq directamente. Abre el archivo en ' ...
               'AcqKnowledge y usa File > Save As > .mat, o convierte con ' ...
               'acq2mat (paquete Python bioread), y apunta "archivo" al .mat.']);
    end
    S = load(archivo);

    % --- datos ---
    if iscell(S.data)
        senal = double(S.data{canal}(:));
    else
        senal = double(S.data(:, canal));
    end

    % --- frecuencia de muestreo ---
    if isfield(S, 'samples_per_second')
        fs = double(S.samples_per_second(1));
    else
        isi = double(S.isi);
        unidades_isi = 'ms';
        if isfield(S, 'isi_units'), unidades_isi = strtrim(char(S.isi_units)); end
        switch lower(unidades_isi)
            case {'ms', 'msec'}, fs = 1000 / isi;
            case {'sec', 's'},   fs = 1 / isi;
            case {'us', 'usec'}, fs = 1e6 / isi;
            otherwise,           fs = 1000 / isi;   % AcqKnowledge usa ms por defecto
        end
    end

    % --- etiquetas ---
    etiqueta = sprintf('Canal %d', canal);
    unidad   = 'mV';
    if isfield(S, 'labels'), L = cellstr(S.labels); etiqueta = strtrim(L{canal}); end
    if isfield(S, 'units'),  U = cellstr(S.units);  unidad   = strtrim(U{canal}); end
end

function segs = seleccionar_interactivo(t, senal, unidad)
% Alterna entre ZOOM/PAN y seleccion de segmentos.
%   1) Haz zoom (rueda del mouse o barra de herramientas) -> tecla para continuar
%   2) Clic en inicio y fin del segmento
%   ENTER (sin clic) en la fase 2 = terminar
fig = figure('Name','Seleccion de segmentos','Color','w');
ax = axes(fig); hold(ax, 'on');
plot(ax, t, senal, 'Color', [0 0.447 0.741]); grid(ax, 'on');
xlabel(ax, 'Tiempo (s)'); ylabel(ax, unidad);
xlim_full = [t(1) t(end)];
ylim_full = ylim(ax);
segs = [];

% Zoom con la rueda del mouse (centrado en el cursor)
fig.WindowScrollWheelFcn = @(~, ev) zoom_rueda(ax, ev);

while true
    title(ax, 'ZOOM: rueda / lupa / mano. Presiona una TECLA para elegir segmento');
    zoom(fig, 'on');
    waitforbuttonpress;            % espera una tecla (o clic)
    zoom(fig, 'off');

    title(ax, 'Clic: INICIO y FIN del segmento (ENTER = terminar)');
    [x, ~] = ginput(2);
    if numel(x) < 2, break; end
    x = sort(x(:))';
    segs(end+1, :) = x; %#ok<AGROW>

    % Parche con altura fija (no depende del zoom actual)
    patch(ax, x([1 2 2 1]), ylim_full([1 1 2 2]), [0.85 0.33 0.10], ...
        'FaceAlpha', 0.3, 'EdgeColor', 'none');
end
disp('Segmentos seleccionados (s):'); disp(segs);
end

function zoom_rueda(ax, ev)
factor = 1.25 ^ ev.VerticalScrollCount;      % rueda arriba = acercar
cp = ax.CurrentPoint(1, 1);                  % x bajo el cursor
xl = xlim(ax);
xlim(ax, cp + (xl - cp) * factor);
end