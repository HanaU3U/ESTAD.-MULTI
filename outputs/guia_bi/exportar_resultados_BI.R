# Ejecutar desde la raiz del proyecto en RStudio:
# source("outputs/guia_bi/exportar_resultados_BI.R", encoding = "UTF-8")
# Requiere psych, GPArotation y FactoMineR. No instala paquetes ni cambia la fuente.
# Es una propuesta nueva de exportacion. No se ha ejecutado en esta revision.

requeridos <- c("psych", "GPArotation", "FactoMineR")
faltan <- requeridos[!vapply(requeridos, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan)) stop("Instala primero: ", paste(faltan, collapse = ", "))
fuente <- "DATASET/datos_credit.csv"
stopifnot(file.exists(fuente))
hash <- unname(tools::md5sum(fuente))
d <- read.csv(fuente, check.names = FALSE, stringsAsFactors = FALSE)
d$id_fila <- seq_len(nrow(d))
respuesta <- "default payment next month"
cuant <- c("LIMIT_BAL", "AGE", paste0("BILL_AMT", 1:6), paste0("PAY_AMT", 1:6))
historial <- c("PAY_0", paste0("PAY_", 2:6))
stopifnot(all(c(cuant, historial, respuesta) %in% names(d)),
          all(is.finite(as.matrix(d[c(cuant, historial, respuesta)]))),
          all(d[[respuesta]] %in% 0:1), all(d$LIMIT_BAL > 0),
          all(as.matrix(d[paste0("PAY_AMT", 1:6)]) >= 0))
salida <- "DATASET/BI_credito"
dir.create(salida, recursive = TRUE, showWarnings = FALSE)
guardar <- function(x, nombre) {
  write.csv(x, file.path(salida, paste0(nombre, ".csv")),
            row.names = FALSE, fileEncoding = "UTF-8", na = "")
}

# 1. PCA de 14 variables: exactamente el conjunto y orientacion del 31 de octubre.
pca <- prcomp(d[cuant], center = TRUE, scale. = TRUE)
for (k in seq_len(ncol(pca$rotation))) {
  ancla <- if (k <= 3) c("BILL_AMT1", "PAY_AMT1", "AGE")[k] else
    rownames(pca$rotation)[which.max(abs(pca$rotation[, k]))]
  signo <- ifelse(pca$rotation[ancla, k] < 0, -1, 1)
  pca$rotation[, k] <- pca$rotation[, k] * signo
  pca$x[, k] <- pca$x[, k] * signo
}
varianza <- pca$sdev^2 / sum(pca$sdev^2)
guardar(data.frame(modelo_id = "PCA14", componente = seq_along(varianza),
                   autovalor = pca$sdev^2, proporcion = varianza,
                   acumulada = cumsum(varianza)), "bi_pca_ejes")
guardar(do.call(rbind, lapply(seq_along(varianza), function(k) {
  data.frame(modelo_id = "PCA14", variable = cuant, componente = k,
             peso = pca$rotation[, k],
             correlacion = pca$rotation[, k] * pca$sdev[k],
             contribucion = pca$rotation[, k]^2,
             cos2 = (pca$rotation[, k] * pca$sdev[k])^2,
             media_entrenamiento = pca$center, sd_entrenamiento = pca$scale)
})), "bi_pca_variables")
d$C1 <- pca$x[, 1]; d$C2 <- pca$x[, 2]
corte1 <- pca$sdev[1]; corte2 <- -pca$sdev[2]
d$zona_pca <- ifelse(d$C1 > corte1 & d$C2 < corte2, "Ambas revisiones",
                    ifelse(d$C1 > corte1, "Solo facturacion",
                    ifelse(d$C2 < corte2, "Solo contraste de pagos", "Sin senal por estos cortes")))
set.seed(2026)
d$muestra_pca <- as.integer(d$id_fila %in% sample(d$id_fila, min(3000, nrow(d))))

# 2. Factorial de nueve variables. Exportar un factor; dos como sensibilidad.
vars_fa <- c("LIMIT_BAL", "AGE", paste0("BILL_AMT", 1:6), "PAY_AMT6")
Xf <- d[vars_fa]
f1 <- psych::fa(Xf, nfactors = 1, fm = "ml", rotate = "none", scores = "regression")
f2 <- psych::fa(Xf, nfactors = 2, fm = "ml", rotate = "oblimin")
f2min <- psych::fa(Xf, nfactors = 2, fm = "minres", rotate = "oblimin")
carga <- as.numeric(f1$loadings[, 1])
sg <- ifelse(carga[match("BILL_AMT1", vars_fa)] < 0, -1, 1)
carga <- carga * sg
d$factor_facturacion <- f1$scores[, 1] * sg
h2 <- as.numeric(f1$communality)
stopifnot(all(is.finite(h2)), all(h2 >= 0 & h2 <= 1))
guardar(data.frame(modelo_id = "FA9_1_ML", variable = vars_fa,
                   orden = seq_along(vars_fa), carga = carga, comun = h2,
                   propia = 1 - h2, msa = as.numeric(psych::KMO(cor(Xf))$MSAi)),
        "bi_factorial_variables")
modelos_fa <- list(FA9_1_ML = f1, FA9_2_ML = f2, FA9_2_MINRES = f2min)
guardar(do.call(rbind, lapply(names(modelos_fa), function(id) {
  f <- modelos_fa[[id]]
  data.frame(modelo_id = id, kmo = psych::KMO(cor(Xf))$MSA,
             comun_media = mean(f$communality), rmsr = f$rms,
             correlacion_factores = if (is.null(f$Phi)) NA_real_ else f$Phi[1, 2])
})), "bi_factorial_ajuste")
guardar(do.call(rbind, lapply(names(modelos_fa), function(id) {
  f <- modelos_fa[[id]]
  do.call(rbind, lapply(seq_len(ncol(f$loadings)), function(k) {
    data.frame(modelo_id = id, variable = vars_fa, factor = k,
               carga_patron = as.numeric(f$loadings[, k]), comun = f$communality)
  }))
})), "bi_factorial_sensibilidad")

# 3. Mahalanobis y Q-Q. El corte es una referencia, no una probabilidad de impago.
M <- as.matrix(d[cuant]); Mt <- M
Mt[, "LIMIT_BAL"] <- log(M[, "LIMIT_BAL"])
Mt[, paste0("BILL_AMT", 1:6)] <- sign(M[, paste0("BILL_AMT", 1:6)]) *
  log1p(abs(M[, paste0("BILL_AMT", 1:6)]))
Mt[, paste0("PAY_AMT", 1:6)] <- log1p(M[, paste0("PAY_AMT", 1:6)])
d$D2_original <- mahalanobis(M, colMeans(M), cov(M))
d$D2_transformada <- mahalanobis(Mt, colMeans(Mt), cov(Mt))
umbral <- qchisq(.99, ncol(M))
d$revision_maha <- as.integer(d$D2_transformada > umbral)
n <- nrow(d)
# Puntos ordenados representativos; incluye mas puntos en la cola y el maximo.
ix <- sort(unique(c(round(seq(1, n, length.out = min(300, n))),
                    round(seq(max(1, .95*n), n, length.out = min(100, n))))))
teorica <- qchisq(ppoints(n), df = ncol(M))[ix]
guardar(rbind(
  data.frame(orden = ix, teorica, valor = sort(d$D2_original)[ix], serie = "Original"),
  data.frame(orden = ix, teorica, valor = sort(d$D2_transformada)[ix], serie = "Transformada"),
  data.frame(orden = ix, teorica, valor = teorica, serie = "Referencia")), "bi_qq")

# 4. Categorias. Conserva separados -2, -1 y 0. Agrupa atrasos de 3 o mas meses.
# Esta agrupacion es una propuesta para el BI; no modifica los CSV existentes.
categorizar_pago <- function(x) {
  factor(ifelse(x >= 3, "Atraso 3+", ifelse(x == 2, "Atraso 2",
         ifelse(x == 1, "Atraso 1", ifelse(x == -1, "Pago puntual (-1)",
         ifelse(x == 0, "Codigo 0", "Codigo -2"))))),
         levels = c("Codigo -2", "Pago puntual (-1)", "Codigo 0", "Atraso 1", "Atraso 2", "Atraso 3+"))
}
cats <- as.data.frame(lapply(d[historial], categorizar_pago))
cats$EDUCATION <- factor(d$EDUCATION, levels = 1:4, labels = c("Posgrado", "Universidad", "Secundaria", "Otros"))
cats$SEX <- factor(d$SEX, levels = 1:2, labels = c("Hombre", "Mujer"))
cats$MARRIAGE <- factor(d$MARRIAGE, levels = 1:3, labels = c("Casado", "Soltero", "Otros"))
cats$Incumplimiento <- factor(d[[respuesta]], levels = 0:1, labels = c("No", "Si"))
stopifnot(!anyNA(cats))
d$Incumplimiento <- d[[respuesta]]
d$Sexo <- as.character(cats$SEX); d$Educacion <- as.character(cats$EDUCATION)
d$Estado_civil <- as.character(cats$MARRIAGE)
d$Estado_pago <- as.character(cats$PAY_0)
d$Orden_estado <- as.integer(cats$PAY_0)
d$Grupo_edad <- as.character(cut(d$AGE, c(20,29,39,49,Inf),
                        labels = c("21-29", "30-39", "40-49", "50+")))

# 5. Correspondencias simples: todos los pares de las diez variables categoricas.
# No selecciona automaticamente un ganador por p-valor. Ajuste BH exploratorio.
celdas <- puntos <- ejes <- modelos <- list()
pares <- combn(names(cats), 2, simplify = FALSE)
for (par in pares) {
  id <- paste(par, collapse = "__")
  tab <- table(cats[[par[1]]], cats[[par[2]]])
  tab <- tab[rowSums(tab) > 0, colSums(tab) > 0, drop = FALSE]
  dims <- min(dim(tab)) - 1L
  if (dims < 1L) next
  test <- suppressWarnings(chisq.test(tab, correct = FALSE))
  ca <- FactoMineR::CA(tab, ncp = min(2L, dims), graph = FALSE)
  signo <- if (par[2] == "Incumplimiento" && ca$col$coord["Si", 1] < 0) -1 else 1
  rej <- expand.grid(fila = rownames(tab), columna = colnames(tab), stringsAsFactors = FALSE)
  rej$modelo_id <- id
  rej$observado <- as.numeric(tab); rej$esperado <- as.numeric(test$expected)
  rej$residuo_pearson <- as.numeric(test$residuals)
  rej$residuo_ajustado <- as.numeric(test$stdres)
  rej$observado_esperado <- rej$observado / rej$esperado
  rej$proporcion_fila <- as.numeric(prop.table(tab, 1))
  celdas[[id]] <- rej
  for (tipo in c("row", "col")) {
    obj <- ca[[tipo]]
    frecuencia <- if (tipo == "row") rowSums(tab) else colSums(tab)
    puntos[[paste(id,tipo)]] <- data.frame(
      modelo_id = id, tipo = tipo, categoria = rownames(obj$coord),
      punto_id = paste(id, tipo, rownames(obj$coord), sep = "|"),
      dim1 = obj$coord[,1] * signo,
      dim2 = if (ncol(obj$coord) >= 2) obj$coord[,2] else NA_real_,
      cos2_dim1 = obj$cos2[,1],
      cos2_dim2 = if (ncol(obj$cos2) >= 2) obj$cos2[,2] else NA_real_,
      cos2_plano = rowSums(obj$cos2[, seq_len(min(2, ncol(obj$cos2))), drop = FALSE]),
      contrib_dim1 = obj$contrib[,1] / 100,
      contrib_dim2 = if (ncol(obj$contrib) >= 2) obj$contrib[,2] / 100 else NA_real_,
      n_categoria = as.numeric(frecuencia), masa = as.numeric(frecuencia)/sum(tab))
  }
  ejes[[id]] <- data.frame(modelo_id = id, dimension = seq_len(nrow(ca$eig)),
                           autovalor = ca$eig[,1], proporcion = ca$eig[,2]/100,
                           acumulada = ca$eig[,3]/100)
  modelos[[id]] <- data.frame(modelo_id = id, variable_fila = par[1], variable_columna = par[2],
    n = sum(tab), dimensiones = dims, chi2 = unname(test$statistic),
    gl = unname(test$parameter), p = test$p.value,
    V_cramer = sqrt(unname(test$statistic)/(sum(tab)*dims)),
    esperado_min = min(test$expected), celdas_esperado_menor5 = sum(test$expected < 5))
}
modelos <- do.call(rbind, modelos); modelos$p_BH <- p.adjust(modelos$p, method = "BH")
guardar(modelos, "bi_ca_modelos")
guardar(do.call(rbind, celdas), "bi_ca_celdas")
guardar(do.call(rbind, puntos), "bi_ca_puntos")
guardar(do.call(rbind, ejes), "bi_ca_ejes")

# 6. Correspondencias multiples: tres analisis exploratorios distintos.
# Resultado futuro siempre suplementario. Las categorias se prefijan para evitar
# confundir, por ejemplo, "Otros" de escolaridad y de estado civil.
variantes <- list(MCA_historial = historial,
                  MCA_demografia = c("SEX", "EDUCATION", "MARRIAGE"),
                  MCA_mixto = c(historial, "SEX", "EDUCATION", "MARRIAGE"))
mc_cat <- mc_ejes <- mc_ind <- list()
for (id in names(variantes)) {
  activas <- variantes[[id]]
  suplementarias <- setdiff(names(cats), activas)
  nombres <- c(activas, suplementarias)
  entrada <- cats[nombres]
  for (v in nombres) entrada[[v]] <- factor(paste(v, entrada[[v]], sep = "::"))
  mca <- FactoMineR::MCA(entrada, ncp = 5, graph = FALSE,
                        quali.sup = seq.int(length(activas)+1L, length(nombres)))
  mc_ejes[[id]] <- data.frame(modelo_id = id, dimension = seq_len(nrow(mca$eig)),
    autovalor = mca$eig[,1], proporcion_bruta = mca$eig[,2]/100,
    acumulada_bruta = mca$eig[,3]/100)
  for (rol in c("Activa", "Suplementaria")) {
    obj <- if (rol == "Activa") mca$var else mca$quali.sup
    etiquetas <- rownames(obj$coord)
    variable <- sub("::.*$", "", etiquetas)
    categoria <- sub("^[^:]+::", "", etiquetas)
    frecuencia <- mapply(function(v,c) sum(as.character(cats[[v]]) == c), variable, categoria)
    mc_cat[[paste(id,rol)]] <- data.frame(modelo_id = id, rol = rol,
      categoria_id = etiquetas, variable, categoria,
      dim1 = obj$coord[,1], dim2 = obj$coord[,2],
      cos2_plano = rowSums(obj$cos2[,1:2,drop=FALSE]),
      contrib_dim1 = if (rol == "Activa") obj$contrib[,1]/100 else NA_real_,
      contrib_dim2 = if (rol == "Activa") obj$contrib[,2]/100 else NA_real_,
      n_categoria = frecuencia,
      incumplimientos = mapply(function(v,c) sum(d$Incumplimiento[as.character(cats[[v]])==c]), variable, categoria))
  }
  mc_ind[[id]] <- data.frame(modelo_id=id, id_fila=d$id_fila,
    dim1=mca$ind$coord[,1], dim2=mca$ind$coord[,2],
    cos2_plano=rowSums(mca$ind$cos2[,1:2,drop=FALSE]))
}
guardar(do.call(rbind, mc_cat), "bi_mca_categorias")
guardar(do.call(rbind, mc_ejes), "bi_mca_ejes")
guardar(do.call(rbind, mc_ind), "bi_mca_individuos")

# Principal: una fila por cliente. Se une con todos los resultados individuales.
guardar(d, "bi_clientes")
guardar(data.frame(fuente, md5 = hash, n = nrow(d),
                   corte_pca_C1 = corte1, corte_pca_C2 = corte2,
                   corte_maha_D2 = umbral, semilla_muestra = 2026,
                   n_muestra = sum(d$muestra_pca), version_R = R.version.string), "bi_metadatos")
stopifnot(!anyDuplicated(d$id_fila), sum(table(d$zona_pca)) == nrow(d),
          identical(hash, unname(tools::md5sum(fuente))))
capture.output(sessionInfo(), file = file.path(salida, "versiones_paquetes.txt"))
message("Exportaciones guardadas en ", normalizePath(salida, winslash = "/"))
