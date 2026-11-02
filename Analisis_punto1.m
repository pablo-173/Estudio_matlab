%% ANALISIS_EOG_GRUPOS.m  (version sin toolboxes: solo MATLAB base)
% Analisis EOG (521 palabras): grupos A (1.o/2.o) vs B (4.o/5.o), Control aparte.
% Entrada : Base_EOG_521_palabras.xlsx (hoja "Participantes")
%           Eventos_EOG.csv (OPCIONAL; modelos mixtos, requieren Statistics Toolbox)
% Salida  : carpeta Resultados/ con un .xlsx por objetivo
clear; clc; rng(2026);

archivo = 'Base_EOG_521_palabras.xlsx';
outdir  = 'Resultados'; if ~exist(outdir,'dir'), mkdir(outdir); end
UMBRAL_VALIDO = 80;      % % de senal valida (analisis de sensibilidad)
NBOOT = 5000;
ESCN  = {'Principal','Sensibilidad_pct80'};

%% 1. CARGA Y BANDERAS DE INCLUSION
T = readtable(archivo,'Sheet','Participantes');
T.grupo = string(T.grupo);
T.tiene_eog     = ~isnan(T.velocidad_ppm);
T.evento_valido = T.tiene_eog & T.num_fijaciones > 0;     % excluye EOG37 (0 fijaciones)
T.calidad_ok    = T.evento_valido & T.pct_valido >= UMBRAL_VALIDO;

vars   = {'puntaje_15','velocidad_ppm','mediana_fijaciones_ms','mediana_sacadas_ms', ...
          'num_fijaciones','tasa_fijaciones_min','num_sacadas','tasa_sacadas_min','retornos'};
etiq   = {'Comprension (/15)','Velocidad (ppm)','Mediana fijaciones (ms)','Mediana sacadas (ms)', ...
          'N fijaciones','Tasa fijaciones (/min)','N sacadas','Tasa sacadas (/min)','Retornos'};
grupos = {'A','B','Control'};

%% 2. DESCRIPTIVOS POR GRUPO Y POR ANIO
filas = {};
for g = 1:3
    for k = 1:numel(vars)
        m = mascara(T,vars{k},1) & T.grupo==grupos{g};
        x = T.(vars{k})(m); x = x(~isnan(x));
        filas(end+1,:) = {grupos{g},etiq{k},numel(x),mean(x),std(x),median(x), ...
            prctil(x,25),prctil(x,75),min(x),max(x)}; %#ok<SAGROW>
    end
end
Desc = cell2table(filas,'VariableNames',{'Grupo','Variable','n','Media','DE','Mediana','Q1','Q3','Min','Max'});
writetable(Desc,fullfile(outdir,'01_Descriptivos.xlsx'));

anio_txt = string(T.anio_universitario);
anios = unique(anio_txt,'stable');
filas = {};
for a = 1:numel(anios)
    for k = 1:numel(vars)
        m = mascara(T,vars{k},1) & anio_txt==anios(a);
        x = T.(vars{k})(m); x = x(~isnan(x));
        if isempty(x), continue; end
        filas(end+1,:) = {char(anios(a)),etiq{k},numel(x),mean(x),std(x),median(x)}; %#ok<SAGROW>
    end
end
writetable(cell2table(filas,'VariableNames',{'Anio','Variable','n','Media','DE','Mediana'}), ...
    fullfile(outdir,'01_Descriptivos.xlsx'),'Sheet','PorAnio');

%% 3. OBJETIVO 1: B vs A (Welch, Mann-Whitney, Hedges g, Cliff delta, Holm)
Comp = table();
for esc = 1:2
    filas = {};
    for k = 1:numel(vars)
        m = mascara(T,vars{k},esc);
        A = T.(vars{k})(m & T.grupo=='A'); A = A(~isnan(A));
        B = T.(vars{k})(m & T.grupo=='B'); B = B(~isnan(B));
        [tst,pw] = welch(B,A);
        pmw = mannwhitney_p(B,A);
        g   = hedges_g(B,A);
        gb  = zeros(NBOOT,1);
        for b = 1:NBOOT
            gb(b) = hedges_g(B(randi(numel(B),numel(B),1)),A(randi(numel(A),numel(A),1)));
        end
        gci = [prctil(gb(isfinite(gb)),2.5), prctil(gb(isfinite(gb)),97.5)];
        cd  = (sum(sum(B>A.'))-sum(sum(B<A.')))/(numel(A)*numel(B));
        filas(end+1,:) = {etiq{k},numel(A),numel(B),median(A),median(B),mean(A),mean(B), ...
            tst,pw,pmw,g,gci(1),gci(2),cd}; %#ok<SAGROW>
    end
    C = cell2table(filas,'VariableNames',{'Variable','nA','nB','MedianaA','MedianaB','MediaA','MediaB', ...
        't_Welch','p_Welch','p_MannWhitney','g_Hedges','g_IC_inf','g_IC_sup','Cliff_delta'});
    C.p_Holm = holm(C.p_MannWhitney);
    C.Escenario = repmat(ESCN(esc),height(C),1);
    Comp = [Comp; C]; %#ok<AGROW>
end
writetable(Comp,fullfile(outdir,'02_Obj1_Comparaciones.xlsx'));

% Kruskal-Wallis (3 grupos y 4 anios) y tendencia con el anio (A+B)
anio_n = nan(height(T),1);
nm = {'Primer','Segundo','Cuarto','Quinto'}; val = [1 2 4 5];
for i = 1:4, anio_n(startsWith(anio_txt,nm{i})) = val(i); end
filas = {};
for k = 1:numel(vars)
    m = mascara(T,vars{k},1); x = T.(vars{k}); m = m & ~isnan(x);
    p3 = kruskal_p(x(m),T.grupo(m));
    m4 = m & ~isnan(anio_n);
    p4 = kruskal_p(x(m4),anio_n(m4));
    mt = m4 & ismember(T.grupo,["A","B"]);
    [rho,pt] = spearman(anio_n(mt),x(mt));
    filas(end+1,:) = {etiq{k},p3,p4,rho,pt}; %#ok<SAGROW>
end
writetable(cell2table(filas,'VariableNames',{'Variable','p_KW_3grupos','p_KW_4anios','rho_anio','p_tendencia'}), ...
    fullfile(outdir,'02_Obj1_Comparaciones.xlsx'),'Sheet','Anio_y_3grupos');

%% 4. OBJETIVO 2: correlaciones con velocidad, por grupo (Pearson y Spearman)
ys   = {'mediana_fijaciones_ms','mediana_sacadas_ms','tasa_fijaciones_min','tasa_sacadas_min','puntaje_15'};
yeti = {'Mediana fijaciones (ms)','Mediana sacadas (ms)','Tasa fijaciones','Tasa sacadas','Comprension'};
tipo = {'Obj2','Obj2','Complementaria','Complementaria','Complementaria'};
gdef = {'A',["A"]; 'B',["B"]; 'Control',["Control"]; 'A+B',["A","B"]};
Corr = table();
for esc = 1:2
    filas = {};
    for gi = 1:size(gdef,1)
        for j = 1:numel(ys)
            m = mascara(T,ys{j},esc) & mascara(T,'velocidad_ppm',esc) & ismember(T.grupo,gdef{gi,2});
            x = T.velocidad_ppm(m); y = T.(ys{j})(m); ok = ~isnan(x)&~isnan(y); x=x(ok); y=y(ok); n=numel(x);
            if n < 4, continue; end
            [rp,pp] = pearson(x,y);
            [rs,ps] = spearman(x,y);
            cp = ci_r(rp,n,false); cs = ci_r(rs,n,true);
            filas(end+1,:) = {gdef{gi,1},tipo{j},yeti{j},n,rp,pp,cp(1),cp(2),rs,ps,cs(1),cs(2)}; %#ok<SAGROW>
        end
    end
    C = cell2table(filas,'VariableNames',{'Grupo','Tipo','Y_vs_velocidad','n','Pearson_r','p_Pearson', ...
        'IC_inf','IC_sup','Spearman_rho','p_Spearman','IC_inf_rho','IC_sup_rho'});
    C.Escenario = repmat(ESCN(esc),height(C),1);
    Corr = [Corr; C]; %#ok<AGROW>
end
writetable(Corr,fullfile(outdir,'03_Obj2_Correlaciones.xlsx'));

%% 5. OBJETIVO 3: comparar correlaciones A vs B (z de Fisher)
filas = {};
for esc = 1:2
    nomE = ESCN{esc};
    for j = 1:numel(ys)
        for met = {'Pearson','Spearman'}
            sp = strcmp(met{1},'Spearman');
            if sp, col = 'Spearman_rho'; else, col = 'Pearson_r'; end
            a = Corr(strcmp(Corr.Grupo,'A') & strcmp(Corr.Y_vs_velocidad,yeti{j}) & strcmp(Corr.Escenario,nomE),:);
            b = Corr(strcmp(Corr.Grupo,'B') & strcmp(Corr.Y_vs_velocidad,yeti{j}) & strcmp(Corr.Escenario,nomE),:);
            if isempty(a)||isempty(b), continue; end
            r1=a.(col); r2=b.(col); n1=a.n; n2=b.n;
            if sp, v1=(1+r1^2/2)/(n1-3); v2=(1+r2^2/2)/(n2-3);   % Bonett-Wright
            else,  v1=1/(n1-3);          v2=1/(n2-3); end
            z = (atanh(r1)-atanh(r2))/sqrt(v1+v2);
            p = 2*(1-normcdf_(abs(z)));
            filas(end+1,:) = {nomE,tipo{j},yeti{j},met{1},n1,n2,r1,r2,z,p}; %#ok<SAGROW>
        end
    end
end
Fz = cell2table(filas,'VariableNames',{'Escenario','Tipo','Y_vs_velocidad','Metodo','nA','nB','r_A','r_B','z','p'});
writetable(Fz,fullfile(outdir,'04_Obj3_Fisher.xlsx'));
% Nota: Control (n=6) no se compara por falta de potencia.

%% 6. OBJETIVO 4a: MODELOS DE CONTEO (offset = log tiempo valido en min)
filas = {};
for esc = 1:2
    base = T.evento_valido & ismember(T.grupo,["A","B"]);
    if esc==2, base = base & T.pct_valido>=UMBRAL_VALIDO; end
    S = T(base,:);
    X = [ones(height(S),1), double(S.grupo=="B")];            % columna 2: B vs A
    off = log(S.tiempo_valido_s/60);
    for resp = {'num_fijaciones','num_sacadas'}
        y = S.(resp{1}); n = numel(y); pdim = 2;
        % Poisson por IRLS
        beta = [log(mean(y./exp(off))); 0];
        for it = 1:100
            mu = exp(X*beta+off);
            W  = mu; zz = X*beta + (y-mu)./mu;               % (zz sin offset)
            bn = (X'*(X.*W)) \ (X'*(W.*zz));
            if max(abs(bn-beta))<1e-10, beta = bn; break; end
            beta = bn;
        end
        mu = exp(X*beta+off);
        disp_pearson = sum((y-mu).^2./mu)/(n-pdim);
        bread = inv(X'*(X.*mu));
        meat  = X'*(X.*((y-mu).^2));
        Vrob  = n/(n-pdim)*bread*meat*bread;                 % HC1
        b1 = beta(2); se1 = sqrt(Vrob(2,2));
        % Binomial negativa NB2 por maxima verosimilitud
        th0 = [beta; log(0.5)];
        nll = @(th) nb_nll(th,X,y,off);
        opts = optimset('MaxFunEvals',1e5,'MaxIter',1e5,'TolX',1e-10,'TolFun',1e-10);
        th = fminsearch(nll,th0,opts);
        th = fminsearch(nll,th,opts);
        th = fminsearch(nll,th,opts);
        Vnb = inv(numhess(nll,th));
        bnb = th(2); senb = sqrt(Vnb(2,2)); alpha = exp(th(3));
        filas(end+1,:) = {ESCN{esc},resp{1},n,disp_pearson, ...
            exp(b1),exp(b1-1.96*se1),exp(b1+1.96*se1),2*(1-normcdf_(abs(b1/se1))), ...
            alpha,exp(bnb),exp(bnb-1.96*senb),exp(bnb+1.96*senb),2*(1-normcdf_(abs(bnb/senb)))}; %#ok<SAGROW>
    end
end
Cnt = cell2table(filas,'VariableNames',{'Escenario','Respuesta','n','Dispersion_Pearson', ...
    'IRR_Poisson_robusto','IC_inf','IC_sup','p_robusto','alpha_NB','IRR_NB','IC_inf_NB','IC_sup_NB','p_NB'});
writetable(Cnt,fullfile(outdir,'05_Obj4_Conteo.xlsx'));
disp(Cnt);

%% 7. OBJETIVO 4b: MODELOS MIXTOS (requiere Statistics Toolbox y tabla de eventos)
% Tabla en formato largo, UNA FILA POR EVENTO, guardada como Eventos_EOG.csv:
%   ID | grupo | tipo_evento ('fijacion'/'sacada') | inicio_s | duracion_ms | segmento | velocidad_ppm
tiene_tb = license('test','statistics_toolbox');
if exist('Eventos_EOG.csv','file') && tiene_tb
    E = readtable('Eventos_EOG.csv');
    E.ID = categorical(E.ID); E.grupo = categorical(string(E.grupo));
    E = E(ismember(E.grupo,{'A','B'}) & E.duracion_ms>0,:);
    E.grupo = removecats(E.grupo);
    E.logdur = log(E.duracion_ms);
    E.vel_c  = E.velocidad_ppm - mean(E.velocidad_ppm,'omitnan');
    res = {};
    for te = {'fijacion','sacada'}
        Ee = E(strcmp(E.tipo_evento,te{1}),:);
        m1 = fitlme(Ee,'logdur ~ grupo + (1|ID)');
        m2 = fitlme(Ee,'logdur ~ grupo*vel_c + (1|ID)');
        res(end+1,:) = {te{1},'logdur ~ grupo + (1|ID)',m1.ModelCriterion.AIC,disp_coef(m1.Coefficients,'grupo_B')}; %#ok<SAGROW>
        res(end+1,:) = {te{1},'logdur ~ grupo*vel_c + (1|ID)',m2.ModelCriterion.AIC,disp_coef(m2.Coefficients,'grupo_B:vel_c')}; %#ok<SAGROW>
        disp(m1); disp(m2);
    end
    writetable(cell2table(res,'VariableNames',{'Evento','Modelo','AIC','Coef_clave'}), ...
        fullfile(outdir,'06_Obj4_Mixtos.xlsx'));
else
    fprintf('\n[Aviso] Modelos mixtos omitidos (falta Eventos_EOG.csv o la Statistics Toolbox).\n');
end
fprintf('\nListo. Resultados en la carpeta "%s".\n',outdir);

%% ======================= FUNCIONES LOCALES (MATLAB base) =======================
function m = mascara(T,v,esc)
    % esc 1 = principal, 2 = sensibilidad (pct_valido >= 80)
    if strcmp(v,'puntaje_15'), m = true(height(T),1);
    elseif strcmp(v,'velocidad_ppm'), m = T.tiene_eog;
    else, m = T.evento_valido; end
    if esc==2 && ~strcmp(v,'puntaje_15'), m = m & T.pct_valido>=80; end
end

function p = normcdf_(x), p = 0.5*erfc(-x/sqrt(2)); end

function p = t_pval(t,df)            % p bilateral de la t de Student
    p = betainc(df./(df+t.^2),df/2,0.5);
end

function q = prctil(x,p)             % percentil con interpolacion lineal
    x = sort(x(:)); n = numel(x);
    pos = (p/100)*n + 0.5;
    if pos<=1, q = x(1); elseif pos>=n, q = x(n);
    else, lo = floor(pos); q = x(lo) + (pos-lo)*(x(lo+1)-x(lo)); end
end

function r = midranks(x)             % rangos con empates promediados
    x = x(:); [xs,ix] = sort(x); n = numel(x); rs = zeros(n,1); i = 1;
    while i<=n
        j = i; while j<n && xs(j+1)==xs(i), j = j+1; end
        rs(i:j) = (i+j)/2; i = j+1;
    end
    r = zeros(n,1); r(ix) = rs;
end

function [t,p] = welch(a,b)
    n1=numel(a); n2=numel(b); v1=var(a)/n1; v2=var(b)/n2;
    t = (mean(a)-mean(b))/sqrt(v1+v2);
    df = (v1+v2)^2/(v1^2/(n1-1)+v2^2/(n2-1));
    p = t_pval(t,df);
end

function p = mannwhitney_p(a,b)      % aprox. normal con correccion por empates y continuidad
    n1=numel(a); n2=numel(b); n=n1+n2; r = midranks([a(:);b(:)]);
    U = sum(r(1:n1)) - n1*(n1+1)/2;
    [~,~,ic] = unique([a(:);b(:)]); tc = accumarray(ic,1);
    sig2 = n1*n2/12*((n+1) - sum(tc.^3-tc)/(n*(n-1)));
    z = (abs(U-n1*n2/2)-0.5)/sqrt(sig2);
    p = 2*(1-normcdf_(z)); p = min(1,p);
end

function p = kruskal_p(x,g)
    x = x(:); [gl,~,gi] = unique(g(:)); k = numel(gl); n = numel(x);
    r = midranks(x); H = 0;
    for i = 1:k, ni = sum(gi==i); H = H + sum(r(gi==i))^2/ni; end
    H = 12/(n*(n+1))*H - 3*(n+1);
    [~,~,ic] = unique(x); tc = accumarray(ic,1);
    H = H/(1-sum(tc.^3-tc)/(n^3-n));
    p = gammainc(H/2,(k-1)/2,'upper');
end

function [r,p] = pearson(x,y)
    c = corrcoef(x,y); r = c(1,2); n = numel(x);
    p = t_pval(r*sqrt((n-2)/(1-r^2)),n-2);
end

function [r,p] = spearman(x,y)
    [r,p] = pearson(midranks(x),midranks(y));
end

function g = hedges_g(a,b)
    n1=numel(a); n2=numel(b);
    sp = sqrt(((n1-1)*var(a)+(n2-1)*var(b))/(n1+n2-2));
    g  = (mean(a)-mean(b))/sp * (1-3/(4*(n1+n2)-9));
end

function padj = holm(p)
    [ps,idx] = sort(p(:)); m = numel(p); a = zeros(m,1); run = 0;
    for k = 1:m
        run = max(run,(m-k+1)*ps(k)); a(k) = min(1,run);
    end
    padj = zeros(m,1); padj(idx) = a;
end

function ci = ci_r(r,n,sp)
    if sp, se = sqrt((1+r^2/2)/(n-3)); else, se = 1/sqrt(n-3); end
    z = atanh(r); ci = tanh([z-1.96*se, z+1.96*se]);
end

function f = nb_nll(th,X,y,off)
    beta = th(1:end-1); a = exp(th(end));
    mu = exp(X*beta+off); r = 1/a;
    ll = gammaln(y+r)-gammaln(r)-gammaln(y+1)+r*log(r./(r+mu))+y.*log(mu./(r+mu));
    f = -sum(ll);
end

function H = numhess(f,x)
    n = numel(x); H = zeros(n); h = 1e-4*max(abs(x),1);
    for i = 1:n
        for j = 1:n
            ei = zeros(n,1); ej = zeros(n,1); ei(i)=h(i); ej(j)=h(j);
            H(i,j) = (f(x+ei+ej)-f(x+ei-ej)-f(x-ei+ej)+f(x-ei-ej))/(4*h(i)*h(j));
        end
    end
end

function s = disp_coef(c,nombre)
    i = find(strcmp(c.Name,nombre),1);
    if isempty(i), s = 'n/d'; return; end
    s = sprintf('%s: est=%.3f, p=%.3f',nombre,c.Estimate(i),c.pValue(i));
end