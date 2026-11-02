%% =========================================================
%              ANALISIS AUTOMATICO EOG
% =========================================================
%
% ARCHIVOS:
%
% ORIGINAL:
%   - Detectar todos los segmentos de lectura
%   - Obtener duracion aproximada de lectura
%
% CALIBRACION:
%   - Calcular umbral individual
%
% LIMPIO:
%   - Detectar sacadas
%   - Detectar fijaciones
%
% SEGMENTOS VALIDOS:
%   - Primero se detectan en ORIGINAL
%   - Luego se revisa cuanto de cada segmento ORIGINAL
%     permanecio despues de la limpieza
%
% =========================================================

clear;
clc;
close all;


%% =========================================================
% 1. SOLO CAMBIAR ESTOS TRES ARCHIVOS
% =========================================================

archivo_original = 'EOG17.mat';

archivo_calibracion = 'EOG17_calibracion';

archivo_limpio = 'EOG17_limpio.mat';


%% =========================================================
% 2. OPCIONES
% =========================================================

mostrarGraficaSacadas = true;

mostrarGraficaSegmentos = true;


%% =========================================================
% 3. PARAMETROS GENERALES
% =========================================================
kSacada = 6;
% ---------------------------------------------------------
% SACADAS
% ---------------------------------------------------------

% Suavizado antes de calcular velocidad
ventana_suavizado_ms = 5;

% Sensibilidad del detector.
%
% Este factor es IGUAL para todos los participantes,
% pero el umbral numerico cambia segun su calibracion.
%
% Debe validarse manualmente y luego congelarse.
factor_umbral_sacada = 2.5;

% Duraciones aceptadas
duracion_min_sacada_ms = 4;

duracion_max_sacada_ms = 120;

% Une pedazos muy cercanos de una misma sacada
separacion_union_ms = 8;

% Tiempo minimo entre dos sacadas distintas
refractario_ms = 25;

% Amplitud minima relativa a la calibracion
fraccion_amplitud_sacada = 0.004;

% Evitar falsas sacadas producidas por cortes/pegados
proteccion_union_ms = 100;


% ---------------------------------------------------------
% FIJACIONES
% ---------------------------------------------------------

duracion_min_fijacion_ms = 50;

% Para que un intervalo sea fijacion, al menos esta
% fraccion debe presentar velocidad baja
fraccion_estable_fijacion = 0.70;

% Una muestra se considera estable si:
%
% abs(velocidad) < este factor * umbral_sacada
factor_velocidad_fijacion = 0.50;


% ---------------------------------------------------------
% SEGMENTOS
% ---------------------------------------------------------
%
% Un retorno grande descendente:
%
%      __________
%                \
%                 \_______
%
% separa una linea de lectura de la siguiente.
% ---------------------------------------------------------

ventana_segmentos_ms = 20;

ventana_retorno_ms = 40;

separacion_min_retorno_s = 0.80;

fraccion_cal_retorno = 0.20;

factor_ruido_retorno = 4;

% Ignorar fragmentos extremadamente cortos al inicio/final
duracion_min_segmento_s = 0.50;


% ---------------------------------------------------------
% CRITERIO DE SEGMENTO VALIDO
% ---------------------------------------------------------
%
% Por ejemplo:
%
% 1.00 = tiene que quedar 100 % del segmento
% 0.80 = al menos 80 % del segmento debe permanecer
%
% Lo dejo en 80 % para permitir pequeños fragmentos
% eliminados por artefacto.
%
% UNA VEZ VALIDADO, mantener el mismo valor para todos.
% ---------------------------------------------------------

fraccion_min_segmento_valido = 0.80;


%% =========================================================
% 4. CARGAR ARCHIVO ORIGINAL
% =========================================================

O = load(archivo_original);


if ~isfield(O,'data')

    error('El ORIGINAL no contiene la variable "data".');

end


if ~isfield(O,'isi')

    error('El ORIGINAL no contiene la variable "isi".');

end


x_original = ...
    double(O.data(:));


isi = ...
    double(O.isi);


%% FRECUENCIA DE MUESTREO

if isfield(O,'isi_units')

    unidad_isi = ...
        lower(strtrim(char(O.isi_units)));


    if contains(unidad_isi,'ms')

        Fs_original = ...
            1000 / isi;

    elseif strcmp(unidad_isi,'s')

        Fs_original = ...
            1 / isi;

    else

        error('Unidad de isi no reconocida.');

    end

else

    Fs_original = ...
        1000 / isi;

end


N_original = ...
    length(x_original);


t_original = ...
    (0:N_original-1)' / Fs_original;


duracion_original = ...
    N_original / Fs_original;


%% =========================================================
% 5. CARGAR CALIBRACION
% =========================================================

C = load(archivo_calibracion);


if ~isfield(C,'senal_limpia')

    error(['El archivo CALIBRACION no contiene ', ...
           '"senal_limpia".']);

end


x_calibracion = ...
    double(C.senal_limpia(:));


if isfield(C,'fs')

    Fs_calibracion = ...
        double(C.fs);

else

    Fs_calibracion = ...
        Fs_original;

end


if isfield(C,'t_limpia')

    t_calibracion = ...
        double(C.t_limpia(:));

else

    t_calibracion = ...
        (0:length(x_calibracion)-1)' ...
        / Fs_calibracion;

end


fin_calibracion = ...
    max(t_calibracion);


%% =========================================================
% 6. CARGAR ARCHIVO LIMPIO
% =========================================================

L = load(archivo_limpio);


if ~isfield(L,'senal_limpia')

    error(['El archivo LIMPIO no contiene ', ...
           '"senal_limpia".']);

end


x_limpio = ...
    double(L.senal_limpia(:));


if isfield(L,'fs')

    Fs_limpio = ...
        double(L.fs);

else

    Fs_limpio = ...
        Fs_original;

end


% Como el archivo limpio fue recortado y unido,
% usamos tiempo continuo para el analisis de eventos.

t_limpio = ...
    (0:length(x_limpio)-1)' ...
    / Fs_limpio;


duracion_valida = ...
    length(x_limpio) / Fs_limpio;


%% =========================================================
% 7. CARGAR INTERVALOS ELIMINADOS
% =========================================================

if isfield(L,'segmentos_eliminar')

    segmentos_eliminar = ...
        double(L.segmentos_eliminar);


    if isempty(segmentos_eliminar)

        segmentos_eliminar = ...
            zeros(0,2);

    elseif isvector(segmentos_eliminar) && ...
           numel(segmentos_eliminar) == 2

        segmentos_eliminar = ...
            reshape( ...
            segmentos_eliminar,1,2);

    end

else

    segmentos_eliminar = ...
        zeros(0,2);

end


if ~isempty(segmentos_eliminar)

    segmentos_eliminar = ...
        sortrows(segmentos_eliminar,1);

end


%% =========================================================
% 8. ENCONTRAR FIN REAL/APROXIMADO DE LECTURA
% =========================================================
%
% Si el ultimo intervalo eliminado llega hasta el final
% del registro, consideramos su inicio como el momento en
% que termino realmente la lectura.
%
% Ejemplo Control 3:
%
% original:      hasta ~89.824 s
% calibracion:   hasta ~6.597 s
% ultimo corte:  ~87.929 a 89.824 s
%
% lectura aprox:
% 87.929 - 6.597
% =========================================================

fin_lectura = ...
    duracion_original;


tolerancia_final = ...
    max(0.05, ...
        2/Fs_original);


for i = 1:size(segmentos_eliminar,1)

    a = ...
        segmentos_eliminar(i,1);

    b = ...
        segmentos_eliminar(i,2);


    if b >= ...
       duracion_original - tolerancia_final

        if a > fin_calibracion

            fin_lectura = ...
                min(fin_lectura,a);

        end

    end

end


duracion_lectura_aprox = ...
    fin_lectura - ...
    fin_calibracion;


if duracion_lectura_aprox <= 0

    error('La duracion aproximada de lectura no es valida.');

end


%% =========================================================
% 9. AMPLITUD DE CALIBRACION
% =========================================================

P95_cal = ...
    percentilSimple( ...
    x_calibracion,95);


P5_cal = ...
    percentilSimple( ...
    x_calibracion,5);


amplitud_calibracion = ...
    P95_cal - ...
    P5_cal;


%% =========================================================
% 10. CALIBRACION PARA SACADAS
% =========================================================
%
% Guia:
%
% v = diff(x)*Fs
%
% candidatos:
%
% abs(v) > umbral
%
% =========================================================

xcal0 = ...
    detrend(x_calibracion);


ventana_cal = ...
    max(1, ...
    round( ...
    ventana_suavizado_ms/1000 * ...
    Fs_calibracion));


xcal_suave = ...
    movmean( ...
    xcal0, ...
    ventana_cal);


v_cal = ...
    [0; diff(xcal_suave)] ...
    * Fs_calibracion;


%% =========================================================
% 11. ESTIMAR RUIDO DE CALIBRACION
% =========================================================

abs_v_cal = ...
    abs(v_cal);


P60 = ...
    percentilSimple( ...
    abs_v_cal,60);


zona_ruido = ...
    v_cal( ...
    abs_v_cal <= P60);


if isempty(zona_ruido)

    zona_ruido = ...
        v_cal;

end


ruido_velocidad = ...
    madRobusta( ...
    zona_ruido);


umbral_sacada = ...
    median(abs(zona_ruido)) + ...
    kSacada * ...
    ruido_velocidad;


if ~isfinite(umbral_sacada) || ...
   umbral_sacada <= 0

    error('No se pudo calcular el umbral de sacadas.');

end


amplitud_min_sacada = ...
    fraccion_amplitud_sacada * ...
    amplitud_calibracion;


%% =========================================================
% 12. PREPROCESAR ARCHIVO LIMPIO
% =========================================================

x_limpio0 = ...
    detrend(x_limpio);


ventana_limpio = ...
    max(1, ...
    round( ...
    ventana_suavizado_ms/1000 * ...
    Fs_limpio));


x_limpio_suave = ...
    movmean( ...
    x_limpio0, ...
    ventana_limpio);


v_limpio = ...
    [0; diff(x_limpio_suave)] ...
    * Fs_limpio;


%% =========================================================
% 13. ENCONTRAR UNIONES ARTIFICIALES DEL ARCHIVO LIMPIO
% =========================================================
%
% Ejemplo:
%
% ORIGINAL
%
% AAAA [eliminado] BBBB
%
% LIMPIO
%
% AAAABBBB
%     ^
%     union artificial
%
% Ese salto puede parecer una sacada y debe excluirse.
% =========================================================

tiempos_union = [];


if ~isempty(segmentos_eliminar)

    tiempo_eliminado_acumulado = 0;


    for i = 1:size(segmentos_eliminar,1)

        a = ...
            segmentos_eliminar(i,1);

        b = ...
            segmentos_eliminar(i,2);


        % Si no es un corte del inicio ni del final,
        % genera una union dentro de la señal limpia.

        if a > 0 && ...
           b < duracion_original - tolerancia_final

            tiempo_union = ...
                a - ...
                tiempo_eliminado_acumulado;


            tiempos_union(end+1,1) = ...
                tiempo_union;

        end


        tiempo_eliminado_acumulado = ...
            tiempo_eliminado_acumulado + ...
            max(0,b-a);

    end

end


%% =========================================================
% 14. CANDIDATOS A SACADAS
% =========================================================
%
% MOVIMIENTO POSITIVO:
%
%      /
% ____/
%
% MOVIMIENTO NEGATIVO:
%
% ____ 
%     \
%      \
%
% Ambos pueden ser sacadas.
% =========================================================

mascara_sacadas = ...
    abs(v_limpio) > ...
    umbral_sacada;


[inicios,finales] = ...
    agruparMascara( ...
    mascara_sacadas);


%% =========================================================
% 15. UNIR MUESTRAS DE UNA MISMA SACADA
% =========================================================

gap_max = ...
    round( ...
    separacion_union_ms/1000 * ...
    Fs_limpio);


[inicios,finales] = ...
    fusionarEventos( ...
    inicios, ...
    finales, ...
    gap_max);


%% =========================================================
% 16. DURACION DE CADA EVENTO
% =========================================================

duracion_sacadas_ms = ...
    (finales - inicios + 1) ...
    / Fs_limpio ...
    * 1000;


%% =========================================================
% 17. FILTRAR POR DURACION
% =========================================================

aceptar = ...
    duracion_sacadas_ms >= ...
        duracion_min_sacada_ms & ...
    duracion_sacadas_ms <= ...
        duracion_max_sacada_ms;


inicios = ...
    inicios(aceptar);


finales = ...
    finales(aceptar);


duracion_sacadas_ms = ...
    duracion_sacadas_ms(aceptar);


%% =========================================================
% 18. CALCULAR AMPLITUD
% =========================================================

amplitud_sacadas = ...
    x_limpio_suave(finales) - ...
    x_limpio_suave(inicios);


magnitud_amplitud = ...
    abs(amplitud_sacadas);


%% FILTRAR CAMBIOS DEMASIADO PEQUENOS

aceptar = ...
    magnitud_amplitud >= ...
    amplitud_min_sacada;


inicios = ...
    inicios(aceptar);


finales = ...
    finales(aceptar);


duracion_sacadas_ms = ...
    duracion_sacadas_ms(aceptar);


amplitud_sacadas = ...
    amplitud_sacadas(aceptar);


%% =========================================================
% 19. QUITAR SACADAS CERCA DE UNIONES ARTIFICIALES
% =========================================================

mantener = ...
    true(length(inicios),1);


proteccion_union_s = ...
    proteccion_union_ms / 1000;


for i = 1:length(inicios)

    centro_evento = ...
        ((inicios(i)+finales(i))/2 - 1) ...
        / Fs_limpio;


    if ~isempty(tiempos_union)

        if any( ...
            abs( ...
            tiempos_union - ...
            centro_evento) <= ...
            proteccion_union_s)

            mantener(i) = false;

        end

    end

end


inicios = ...
    inicios(mantener);


finales = ...
    finales(mantener);


duracion_sacadas_ms = ...
    duracion_sacadas_ms(mantener);


amplitud_sacadas = ...
    amplitud_sacadas(mantener);


%% =========================================================
% 20. PERIODO REFRACTARIO
% =========================================================
%
% Si aparecen dos detecciones extremadamente juntas,
% conservamos aquella con mayor velocidad.
% =========================================================

if ~isempty(inicios)

    centros = ...
        round( ...
        (inicios + finales)/2);


    intensidad = ...
        zeros(length(inicios),1);


    for i = 1:length(inicios)

        intensidad(i) = ...
            max( ...
            abs( ...
            v_limpio( ...
            inicios(i):finales(i))));

    end


    distancia_minima = ...
        round( ...
        refractario_ms/1000 * ...
        Fs_limpio);


    [inicios, ...
     finales, ...
     duracion_sacadas_ms, ...
     amplitud_sacadas] = ...
        aplicarRefractario( ...
        inicios, ...
        finales, ...
        duracion_sacadas_ms, ...
        amplitud_sacadas, ...
        intensidad, ...
        centros, ...
        distancia_minima);

end


%% =========================================================
% 21. TABLA DE SACADAS
% =========================================================

inicio_sacadas_s = ...
    (inicios-1) ...
    / Fs_limpio;


fin_sacadas_s = ...
    (finales-1) ...
    / Fs_limpio;


direccion = ...
    strings(length(inicios),1);


for i = 1:length(inicios)

    if amplitud_sacadas(i) >= 0

        direccion(i) = ...
            "positiva";

    else

        direccion(i) = ...
            "negativa";

    end

end


Sacadas = ...
    table( ...
    inicio_sacadas_s, ...
    fin_sacadas_s, ...
    duracion_sacadas_ms, ...
    amplitud_sacadas, ...
    direccion, ...
    'VariableNames', ...
    { ...
    'Inicio_s', ...
    'Fin_s', ...
    'Duracion_ms', ...
    'Amplitud_mV', ...
    'Direccion' ...
    });


numero_sacadas = ...
    height(Sacadas);


if duracion_valida > 0

    tasa_sacadas = ...
        numero_sacadas / ...
        (duracion_valida/60);

else

    tasa_sacadas = NaN;

end


if numero_sacadas > 0

    duracion_mediana_sacada = ...
        median( ...
        Sacadas.Duracion_ms);

else

    duracion_mediana_sacada = ...
        NaN;

end


%% =========================================================
% 22. FIJACIONES
% =========================================================
%
% Una fijacion debe:
%
% 1. Estar entre dos sacadas.
% 2. Durar al menos el tiempo minimo.
% 3. Ser relativamente estable/plana.
%
% Se comprueba que una proporcion suficiente de muestras
% tenga velocidad baja.
% =========================================================

inicio_fijacion = [];

fin_fijacion = [];

duracion_fijacion = [];

estabilidad_fijacion = [];


umbral_velocidad_fijacion = ...
    factor_velocidad_fijacion * ...
    umbral_sacada;


if numero_sacadas >= 2

    for i = 1:numero_sacadas-1

        idx_inicio = ...
            finales(i) + 1;


        idx_fin = ...
            inicios(i+1) - 1;


        if idx_fin <= idx_inicio

            continue;

        end


        dur_ms = ...
            (idx_fin - idx_inicio + 1) ...
            / Fs_limpio ...
            * 1000;


        if dur_ms < ...
           duracion_min_fijacion_ms

            continue;

        end


        velocidad_intervalo = ...
            abs( ...
            v_limpio( ...
            idx_inicio:idx_fin));


        proporcion_estable = ...
            mean( ...
            velocidad_intervalo < ...
            umbral_velocidad_fijacion);


        if proporcion_estable >= ...
           fraccion_estable_fijacion

            inicio_fijacion(end+1,1) = ...
                (idx_inicio-1) / ...
                Fs_limpio;


            fin_fijacion(end+1,1) = ...
                (idx_fin-1) / ...
                Fs_limpio;


            duracion_fijacion(end+1,1) = ...
                dur_ms;


            estabilidad_fijacion(end+1,1) = ...
                proporcion_estable;

        end

    end

end


Fijaciones = ...
    table( ...
    inicio_fijacion, ...
    fin_fijacion, ...
    duracion_fijacion, ...
    estabilidad_fijacion, ...
    'VariableNames', ...
    { ...
    'Inicio_s', ...
    'Fin_s', ...
    'Duracion_ms', ...
    'Fraccion_estable' ...
    });


numero_fijaciones = ...
    height(Fijaciones);


if duracion_valida > 0

    tasa_fijaciones = ...
        numero_fijaciones / ...
        (duracion_valida/60);

else

    tasa_fijaciones = ...
        NaN;

end


if numero_fijaciones > 0

    duracion_mediana_fijacion = ...
        median( ...
        Fijaciones.Duracion_ms);

else

    duracion_mediana_fijacion = ...
        NaN;

end


%% =========================================================
% 23. DETECTAR RETORNOS EN ORIGINAL
% =========================================================
%
% IMPORTANTE:
%
% LOS SEGMENTOS SIEMPRE NACEN DEL ORIGINAL.
%
% No se vuelven a detectar en el limpio.
% =========================================================

usar_original = ...
    t_original >= ...
        fin_calibracion & ...
    t_original <= ...
        fin_lectura;


x_lectura_original = ...
    x_original(usar_original);


t_lectura_original = ...
    t_original(usar_original);


[retornos_original, ...
 umbral_retorno] = ...
    detectarRetornos( ...
    x_lectura_original, ...
    t_lectura_original, ...
    Fs_original, ...
    amplitud_calibracion, ...
    ventana_segmentos_ms, ...
    ventana_retorno_ms, ...
    separacion_min_retorno_s, ...
    fraccion_cal_retorno, ...
    factor_ruido_retorno);


%% =========================================================
% 24. CONSTRUIR TODOS LOS SEGMENTOS DEL ORIGINAL
% =========================================================
%
% Ahora contamos tambien:
%
% inicio lectura -> primer retorno
%
% y:
%
% ultimo retorno -> fin lectura
%
% siempre que duren lo suficiente.
%
% Esto evita perder la primera o ultima linea.
% =========================================================

limites = ...
    [ ...
    fin_calibracion; ...
    retornos_original(:); ...
    fin_lectura ...
    ];


limites = ...
    unique( ...
    limites, ...
    'stable');


inicio_segmento = ...
    limites(1:end-1);


fin_segmento = ...
    limites(2:end);


duracion_segmento = ...
    fin_segmento - ...
    inicio_segmento;


% Quitar pedazos demasiado cortos

aceptar_segmento = ...
    duracion_segmento >= ...
    duracion_min_segmento_s;


inicio_segmento = ...
    inicio_segmento( ...
    aceptar_segmento);


fin_segmento = ...
    fin_segmento( ...
    aceptar_segmento);


duracion_segmento = ...
    duracion_segmento( ...
    aceptar_segmento);


%% =========================================================
% 25. COMPARAR CADA SEGMENTO ORIGINAL CON LO QUE SE USO
% =========================================================
%
% Para cada segmento ORIGINAL calculamos:
%
% duracion conservada
% -------------------
% duracion original
%
% Si supera el criterio definido arriba, es valido/usado.
%
% ESTO ES LO QUE AHORA COMPARA:
%
% SEGMENTOS DEL ORIGINAL
%          VS
% CUANTO DE ELLOS QUEDO EN EL LIMPIO
%
% =========================================================

Nsegmentos = ...
    length(inicio_segmento);


duracion_eliminada_segmento = ...
    zeros(Nsegmentos,1);


duracion_conservada_segmento = ...
    zeros(Nsegmentos,1);


fraccion_conservada = ...
    zeros(Nsegmentos,1);


segmento_valido = ...
    false(Nsegmentos,1);


for i = 1:Nsegmentos

    a_seg = ...
        inicio_segmento(i);


    b_seg = ...
        fin_segmento(i);


    tiempo_eliminado = 0;


    for j = 1:size(segmentos_eliminar,1)

        a_elim = ...
            segmentos_eliminar(j,1);


        b_elim = ...
            segmentos_eliminar(j,2);


        solapamiento = ...
            max( ...
            0, ...
            min(b_seg,b_elim) - ...
            max(a_seg,a_elim));


        tiempo_eliminado = ...
            tiempo_eliminado + ...
            solapamiento;

    end


    tiempo_eliminado = ...
        min( ...
        tiempo_eliminado, ...
        duracion_segmento(i));


    duracion_eliminada_segmento(i) = ...
        tiempo_eliminado;


    duracion_conservada_segmento(i) = ...
        duracion_segmento(i) - ...
        tiempo_eliminado;


    fraccion_conservada(i) = ...
        duracion_conservada_segmento(i) / ...
        duracion_segmento(i);


    segmento_valido(i) = ...
        fraccion_conservada(i) >= ...
        fraccion_min_segmento_valido;

end


Segmentos = ...
    table( ...
    inicio_segmento, ...
    fin_segmento, ...
    duracion_segmento, ...
    duracion_conservada_segmento, ...
    fraccion_conservada, ...
    segmento_valido, ...
    'VariableNames', ...
    { ...
    'Inicio_s', ...
    'Fin_s', ...
    'Duracion_original_s', ...
    'Duracion_conservada_s', ...
    'Fraccion_conservada', ...
    'Valido' ...
    });


Segmentos_totales = ...
    height(Segmentos);


Segmentos_validos = ...
    sum( ...
    Segmentos.Valido);


Segmentos_invalidos = ...
    Segmentos_totales - ...
    Segmentos_validos;


%% =========================================================
% 26. PORCENTAJE DE SEÑAL VALIDA
% =========================================================

if duracion_lectura_aprox > 0

    porcentaje_valido = ...
        100 * ...
        duracion_valida / ...
        duracion_lectura_aprox;

else

    porcentaje_valido = ...
        NaN;

end


if isfinite(porcentaje_valido)

    porcentaje_valido = ...
        min(porcentaje_valido,100);

end


%% =========================================================
% 27. ID
% =========================================================

[~,ID,~] = ...
    fileparts( ...
    archivo_original);


%% =========================================================
% 28. MOSTRAR RESULTADOS
% =========================================================

fprintf('\n');

fprintf('============================================================\n');
fprintf('                 ANALISIS EOG - %s\n',ID);
fprintf('============================================================\n\n');


fprintf('INFORMACION DEL REGISTRO\n');
fprintf('------------------------------------------------------------\n');

fprintf('Frecuencia de muestreo:              %.2f Hz\n', ...
    Fs_original);

fprintf('Duracion total del archivo:          %.3f s\n', ...
    duracion_original);

fprintf('\n');


fprintf('CALIBRACION\n');
fprintf('------------------------------------------------------------\n');

fprintf('Fin de calibracion:                  %.3f s\n', ...
    fin_calibracion);

fprintf('Amplitud calibracion P95-P5:         %.6f mV\n', ...
    amplitud_calibracion);

fprintf('Umbral individual sacadas:           %.6f mV/s\n', ...
    umbral_sacada);

fprintf('Amplitud minima sacada:              %.6f mV\n', ...
    amplitud_min_sacada);

fprintf('\n');


fprintf('SACADAS - ARCHIVO LIMPIO\n');
fprintf('------------------------------------------------------------\n');

fprintf('Numero de sacadas:                   %d\n', ...
    numero_sacadas);

fprintf('Tasa de sacadas:                     %.2f sacadas/min\n', ...
    tasa_sacadas);

fprintf('Duracion mediana de sacadas:         %.2f ms\n', ...
    duracion_mediana_sacada);

fprintf('\n');


fprintf('FIJACIONES - ARCHIVO LIMPIO\n');
fprintf('------------------------------------------------------------\n');

fprintf('Numero de fijaciones:                %d\n', ...
    numero_fijaciones);

fprintf('Tasa de fijaciones:                  %.2f fijaciones/min\n', ...
    tasa_fijaciones);

fprintf('Duracion mediana fijaciones:         %.2f ms\n', ...
    duracion_mediana_fijacion);

fprintf('\n');


fprintf('SEGMENTOS\n');
fprintf('------------------------------------------------------------\n');

fprintf('Retornos detectados en original:     %d\n', ...
    length(retornos_original));

fprintf('Segmentos totales del original:      %d\n', ...
    Segmentos_totales);

fprintf('Segmentos validos/usados:            %d\n', ...
    Segmentos_validos);

fprintf('Segmentos no validos:                %d\n', ...
    Segmentos_invalidos);

fprintf('Criterio minimo conservado:          %.0f %%\n', ...
    fraccion_min_segmento_valido*100);

fprintf('\n');


fprintf('TIEMPOS\n');
fprintf('------------------------------------------------------------\n');

fprintf('Inicio lectura aprox:                %.3f s\n', ...
    fin_calibracion);

fprintf('Fin lectura aprox:                   %.3f s\n', ...
    fin_lectura);

fprintf('DURACION APROXIMADA DE LECTURA:      %.3f s\n', ...
    duracion_lectura_aprox);

fprintf('Tiempo de senal limpia/valida:       %.3f s\n', ...
    duracion_valida);

fprintf('Porcentaje valido:                   %.2f %%\n', ...
    porcentaje_valido);

fprintf('\n');


%% =========================================================
% CONTROL DE CALIDAD PEDIDO
% =========================================================

fprintf('CONTROL DE CALIDAD\n');
fprintf('------------------------------------------------------------\n');

fprintf('%-15s %-20s %-20s\n', ...
    'Duracion_s', ...
    'Segmentos_totales', ...
    'Segmentos_validos');


fprintf('%-15.3f %-20d %-20d\n', ...
    duracion_lectura_aprox, ...
    Segmentos_totales, ...
    Segmentos_validos);

fprintf('------------------------------------------------------------\n');


%% =========================================================
% RELACION SACADAS / SEGMENTOS
% =========================================================

fprintf('\nVERIFICACION\n');
fprintf('------------------------------------------------------------\n');


if Segmentos_validos > 0

    fprintf('Sacadas promedio/segmento valido:    %.2f\n', ...
        numero_sacadas / ...
        Segmentos_validos);

else

    fprintf('Sacadas promedio/segmento valido:    No calculable\n');

end


fprintf('------------------------------------------------------------\n');


%% =========================================================
% DETALLE DE SEGMENTOS
% =========================================================

fprintf('\nDETALLE DE SEGMENTOS ORIGINALES\n');

fprintf('------------------------------------------------------------\n');

fprintf('%-8s %-10s %-10s %-12s %-12s %-10s\n', ...
    'Seg.', ...
    'Inicio', ...
    'Fin', ...
    'Duracion', ...
    '% conservado', ...
    'Valido');


for i = 1:height(Segmentos)

    if Segmentos.Valido(i)

        txt = 'SI';

    else

        txt = 'NO';

    end


    fprintf('%-8d %-10.3f %-10.3f %-12.3f %-12.1f %-10s\n', ...
        i, ...
        Segmentos.Inicio_s(i), ...
        Segmentos.Fin_s(i), ...
        Segmentos.Duracion_original_s(i), ...
        100*Segmentos.Fraccion_conservada(i), ...
        txt);

end


fprintf('------------------------------------------------------------\n');


%% =========================================================
% 29. GRAFICA DE SACADAS Y FIJACIONES
% =========================================================

if mostrarGraficaSacadas

    figure( ...
        'Name',['Sacadas y fijaciones - ' ID], ...
        'Color','w');


    plot( ...
        t_limpio, ...
        x_limpio, ...
        'k');


    hold on;


    % SACADAS
    %
    % Verde = inicio
    % Rojo  = final

    for i = 1:height(Sacadas)

        xline( ...
            Sacadas.Inicio_s(i), ...
            '--g', ...
            'LineWidth',0.7);


        xline( ...
            Sacadas.Fin_s(i), ...
            '--r', ...
            'LineWidth',0.7);

    end


    % Centro de fijaciones

    for i = 1:height(Fijaciones)

        centro = ...
            (Fijaciones.Inicio_s(i) + ...
             Fijaciones.Fin_s(i))/2;


        indice = ...
            min( ...
            length(x_limpio), ...
            max(1, ...
            round(centro*Fs_limpio)+1));


        plot( ...
            centro, ...
            x_limpio(indice), ...
            'bo', ...
            'MarkerSize',5);

    end


    xlabel('Tiempo de señal valida (s)');

    ylabel('EOG (mV)');

    title(['Sacadas y fijaciones - ' ID]);

    grid on;

    hold off;

end


%% =========================================================
% 30. GRAFICA DE SEGMENTOS DEL ORIGINAL
% =========================================================
%
% Todos los segmentos salen del ORIGINAL.
%
% Verde = segmento valido/usado
% Rojo  = segmento demasiado afectado por limpieza
% =========================================================

if mostrarGraficaSegmentos

    figure( ...
        'Name',['Segmentos - ' ID], ...
        'Color','w');


    plot( ...
        t_original, ...
        x_original, ...
        'k');


    hold on;


    for i = 1:height(Segmentos)

        centro = ...
            (Segmentos.Inicio_s(i) + ...
             Segmentos.Fin_s(i))/2;


        indice = ...
            min( ...
            length(x_original), ...
            max(1, ...
            round(centro*Fs_original)+1));


        if Segmentos.Valido(i)

            plot( ...
                centro, ...
                x_original(indice), ...
                'go', ...
                'MarkerSize',8, ...
                'LineWidth',2);

        else

            plot( ...
                centro, ...
                x_original(indice), ...
                'ro', ...
                'MarkerSize',8, ...
                'LineWidth',2);

        end


        xline( ...
            Segmentos.Fin_s(i), ...
            ':', ...
            'LineWidth',0.7);

    end


    xline( ...
        fin_calibracion, ...
        '--b', ...
        'Inicio lectura');


    xline( ...
        fin_lectura, ...
        '--b', ...
        'Fin lectura');


    xlabel('Tiempo original (s)');

    ylabel('EOG (mV)');

    title( ...
        ['Original: ' ...
         num2str(Segmentos_totales) ...
         ' segmentos; validos: ' ...
         num2str(Segmentos_validos)]);


    xlim( ...
        [fin_calibracion ...
         fin_lectura]);


    grid on;

    hold off;

end


%% =========================================================
%                    FUNCIONES
% =========================================================


function [retornos_t,umbral] = ...
    detectarRetornos( ...
    x, ...
    t, ...
    Fs, ...
    amplitud_cal, ...
    ventana_suavizado_ms, ...
    ventana_retorno_ms, ...
    separacion_min_s, ...
    fraccion_cal, ...
    factor_ruido)

    x = x(:);

    t = t(:);


    ventana = ...
        max(1, ...
        round( ...
        ventana_suavizado_ms/1000 * Fs));


    suave = ...
        movmean(x,ventana);


    lag = ...
        max(1, ...
        round( ...
        ventana_retorno_ms/1000 * Fs));


    delta = ...
        NaN(size(suave));


    for i = lag+1 : ...
            length(suave)-lag

        delta(i) = ...
            suave(i+lag) - ...
            suave(i-lag);

    end


    valores = ...
        delta(isfinite(delta));


    if isempty(valores)

        retornos_t = [];

        umbral = NaN;

        return;

    end


    ruido = ...
        madRobusta(valores);


    umbral_ruido = ...
        median(abs(valores)) + ...
        factor_ruido * ruido;


    umbral_cal = ...
        fraccion_cal * ...
        amplitud_cal;


    umbral = ...
        max( ...
        umbral_ruido, ...
        umbral_cal);


    % Solo retornos DESCENDENTES

    fuerza = ...
        -delta;


    fuerza( ...
        ~isfinite(fuerza)) = 0;


    fuerza(fuerza < 0) = 0;


    distancia_min = ...
        round( ...
        separacion_min_s * Fs);


    [~,loc] = ...
        detectarPicosSinToolbox( ...
        fuerza, ...
        umbral, ...
        distancia_min, ...
        0.30*umbral);


    retornos_t = ...
        t(loc);

end


function [inicios2,finales2] = ...
    fusionarEventos( ...
    inicios, ...
    finales, ...
    max_gap)

    if isempty(inicios)

        inicios2 = [];

        finales2 = [];

        return;

    end


    inicios2 = ...
        inicios(1);


    finales2 = ...
        finales(1);


    for i = 2:length(inicios)

        gap = ...
            inicios(i) - ...
            finales2(end) - 1;


        if gap <= max_gap

            finales2(end) = ...
                finales(i);

        else

            inicios2(end+1,1) = ...
                inicios(i);


            finales2(end+1,1) = ...
                finales(i);

        end

    end


    inicios2 = ...
        inicios2(:);


    finales2 = ...
        finales2(:);

end


function [inicios,finales,duracion,amplitud] = ...
    aplicarRefractario( ...
    inicios, ...
    finales, ...
    duracion, ...
    amplitud, ...
    intensidad, ...
    centros, ...
    distancia_min)

    if length(inicios) <= 1

        return;

    end


    [~,orden] = ...
        sort( ...
        intensidad, ...
        'descend');


    seleccionados = [];


    for k = 1:length(orden)

        idx = ...
            orden(k);


        if isempty(seleccionados)

            seleccionados = idx;

        else

            diferencia = ...
                abs( ...
                centros(idx) - ...
                centros(seleccionados));


            if all( ...
                diferencia >= ...
                distancia_min)

                seleccionados(end+1,1) = ...
                    idx;

            end

        end

    end


    seleccionados = ...
        sort(seleccionados);


    inicios = ...
        inicios(seleccionados);


    finales = ...
        finales(seleccionados);


    duracion = ...
        duracion(seleccionados);


    amplitud = ...
        amplitud(seleccionados);

end


function [inicios,finales] = ...
    agruparMascara(mascara)

    mascara = ...
        logical(mascara(:));


    cambios = ...
        diff( ...
        [false; ...
         mascara; ...
         false]);


    inicios = ...
        find(cambios == 1);


    finales = ...
        find(cambios == -1) - 1;

end


function m = madRobusta(x)

    x = ...
        x(isfinite(x));


    if isempty(x)

        m = NaN;

        return;

    end


    mediana = ...
        median(x);


    m = ...
        median( ...
        abs(x-mediana));

end


function q = percentilSimple(x,p)

    x = ...
        x(isfinite(x));


    x = ...
        sort(x(:));


    if isempty(x)

        q = NaN;

        return;

    end


    if length(x) == 1

        q = x(1);

        return;

    end


    posicion = ...
        1 + ...
        (length(x)-1) * ...
        p/100;


    inferior = ...
        floor(posicion);


    superior = ...
        ceil(posicion);


    if inferior == superior

        q = ...
            x(inferior);

    else

        fraccion = ...
            posicion - inferior;


        q = ...
            x(inferior) + ...
            fraccion * ...
            (x(superior)-x(inferior));

    end

end


function [picos,locs] = ...
    detectarPicosSinToolbox( ...
    y, ...
    minHeight, ...
    minDistance, ...
    minProminence)

    y = y(:);

    N = length(y);


    if N < 3

        picos = [];

        locs = [];

        return;

    end


    candidatos = [];


    %% MAXIMOS LOCALES

    for i = 2:N-1

        if y(i) >= y(i-1) && ...
           y(i) > y(i+1) && ...
           y(i) >= minHeight

            candidatos(end+1,1) = ...
                i;

        end

    end


    if isempty(candidatos)

        picos = [];

        locs = [];

        return;

    end


    %% PROMINENCIA

    radio = ...
        max( ...
        1, ...
        round(minDistance/2));


    conservar = ...
        false( ...
        length(candidatos),1);


    for k = 1:length(candidatos)

        idx = ...
            candidatos(k);


        izq = ...
            max(1,idx-radio);


        der = ...
            min(N,idx+radio);


        baseIzq = ...
            min(y(izq:idx));


        baseDer = ...
            min(y(idx:der));


        baseLocal = ...
            max( ...
            baseIzq, ...
            baseDer);


        prominencia = ...
            y(idx) - ...
            baseLocal;


        if prominencia >= ...
           minProminence

            conservar(k) = true;

        end

    end


    candidatos = ...
        candidatos(conservar);


    if isempty(candidatos)

        picos = [];

        locs = [];

        return;

    end


    %% DISTANCIA MINIMA

    amplitudes = ...
        y(candidatos);


    [~,orden] = ...
        sort( ...
        amplitudes, ...
        'descend');


    seleccionados = [];


    for k = 1:length(orden)

        idx = ...
            candidatos(orden(k));


        if isempty(seleccionados)

            seleccionados = ...
                idx;

        else

            distancia = ...
                abs( ...
                seleccionados - idx);


            if all( ...
                distancia >= ...
                minDistance)

                seleccionados(end+1,1) = ...
                    idx;

            end

        end

    end


    locs = ...
        sort(seleccionados);


    picos = ...
        y(locs);

end