---

editor_options: 
  markdown: 
    wrap: 72
---

# Checklist — ¿mi dataset sirve para el sábado?

**Estadística Multidimensional · 26158 · grupo 020‑81** **Para la sesión del sábado 5 de septiembre y el Taller 2**

------------------------------------------------------------------------

## Antes que nada

Su dataset **ya está aprobado** desde el 24 de agosto — no hay que volver a escogerlo ni cambiarlo. Este checklist es para otra cosa: **verificar que está listo para lo que vamos a hacer el sábado**, que es calcular la matriz de covarianzas, la de correlaciones y las distancias de Mahalanobis.

Son cinco minutos. Y hay dos puntos donde los datasets se caen, que casi nadie mira. Vale la pena correrlo **antes del sábado**, no en clase.

------------------------------------------------------------------------

## Los cinco puntos

### 1 · Solo las columnas numéricas continuas

La matriz de covarianzas **solo se calcula con variables numéricas**. Antes de empezar, sepárelas:

``` r
datos <- read.csv("su_archivo.csv")          # si el separador es ";", use read.csv2()
X <- datos[, sapply(datos, is.numeric)]
dim(X)
```

⚠️ **Ojo con las numéricas disfrazadas.** Un código de municipio, un año, un estrato o un ID llegan como número pero **no son magnitudes**. Si quedan dentro de `X`, la matriz de covarianzas va a mezclar peras con manzanas. Quítelas a mano:

``` r
X <- X[, !(names(X) %in% c("id", "codigo_municipio", "anio"))]
```

------------------------------------------------------------------------

### 2 · Más filas que variables — y con margen

Para que la matriz de covarianzas se pueda **invertir** —que es lo que necesita Mahalanobis— hace falta que **n sea mayor que p**. Y no por poco: con n apenas mayor que p, la inversa sale inestable.

``` r
n <- nrow(X); p <- ncol(X)
cat("n =", n, " p =", p, " n/p =", round(n/p, 1), "\n")
```

✅ **n/p mayor que 10** — cómodo ⚠️ **entre 5 y 10** — funciona, pero los resultados de la unidad 6 van a ser frágiles ❌ **menor que 5** — Mahalanobis va a dar problemas

------------------------------------------------------------------------

### 3 · Faltantes bajo control

`cov()` y `cor()` con `use = "pairwise.complete.obs"` funcionan con huecos. Pero **`mahalanobis()` no**: necesita filas completas.

``` r
cat("% de faltantes:", round(100 * mean(is.na(X)), 1), "\n")
cat("filas completas:", sum(complete.cases(X)), "de", nrow(X), "\n")
```

✅ Si le quedan **al menos 100 filas completas**, va bien ⚠️ Si le quedan menos, tiene que imputar o quitar la columna que más huecos aporta:

``` r
sort(colSums(is.na(X)), decreasing = TRUE)[1:5]   # las cinco peores
```

------------------------------------------------------------------------

### 4 · Que haya estructura — que las variables se muevan juntas

Si todas las variables son independientes entre sí, la matriz de correlación es casi toda ceros y **no hay nada que interpretar**.

``` r
R <- cor(X, use = "pairwise.complete.obs")
diag(R) <- NA
cat("|r| máxima:", round(max(abs(R), na.rm = TRUE), 2), "\n")
cat("pares con |r| > 0.5:", sum(abs(R) > 0.5, na.rm = TRUE) / 2, "\n")
```

✅ **\|r\| máxima por encima de 0,5** y al menos tres o cuatro pares fuertes ❌ **\|r\| máxima por debajo de 0,3** — avise, porque ese dataset no da para la unidad 6

------------------------------------------------------------------------

### 5 · El que nadie mira: columnas redundantes

**Este es el punto que hace fallar la clase del sábado**, y por eso está aquí.

Si una columna es **combinación de otras** —el total que es la suma de las partes, el porcentaje que sale de dos columnas que también están, la misma variable en dos unidades— entonces la nube es *plana*: vive en menos dimensiones de las que dice tener. El determinante de la matriz de covarianzas se va a cero, **la matriz no se puede invertir, y Mahalanobis no se puede calcular**.

``` r
S <- cov(X, use = "pairwise.complete.obs")
cat("determinante:", format(det(S), scientific = TRUE), "\n")

vp <- eigen(S)$values
cat("valor propio más pequeño:", format(min(vp), scientific = TRUE), "\n")
cat("número de condición:", round(max(vp)/min(vp)), "\n")
```

✅ **Número de condición por debajo de 1.000** — todo bien ⚠️ **entre 1.000 y 100.000** — hay variables muy parecidas, revise ❌ **por encima de 100.000, o determinante prácticamente cero** — **hay redundancia**

**Cómo encontrar la culpable:**

``` r
R2 <- abs(cor(X, use = "pairwise.complete.obs")); diag(R2) <- 0
which(R2 > 0.95, arr.ind = TRUE)      # pares casi idénticos
```

**Qué hacer si aparece:** quite **una** de las dos. Si es un total que suma otras columnas, quite el total —es el que no aporta información nueva—. Anótelo: **esa decisión va en el informe**, y es justo el tipo de cosa que se pregunta en la sustentación.

------------------------------------------------------------------------

## Todo junto — copie y corra esto

``` r
revisar <- function(ruta, quitar = character(0)) {
  d <- read.csv(ruta)
  X <- d[, sapply(d, is.numeric), drop = FALSE]
  X <- X[, !(names(X) %in% quitar), drop = FALSE]
  n <- nrow(X); p <- ncol(X)

  cat("=====", ruta, "=====\n")
  cat("1. variables numéricas usadas:", p, "\n   ", paste(names(X), collapse = ", "), "\n\n")
  cat("2. n =", n, "| p =", p, "| n/p =", round(n/p, 1),
      ifelse(n/p >= 10, " OK", ifelse(n/p >= 5, " justo", " PROBLEMA")), "\n\n")
  cat("3. faltantes:", round(100*mean(is.na(X)), 1), "% | filas completas:",
      sum(complete.cases(X)), ifelse(sum(complete.cases(X)) >= 100, " OK", " PROBLEMA"), "\n\n")

  R <- cor(X, use = "pairwise.complete.obs"); diag(R) <- NA
  rmax <- max(abs(R), na.rm = TRUE)
  cat("4. |r| máxima:", round(rmax, 2),
      ifelse(rmax >= 0.5, " OK", ifelse(rmax >= 0.3, " justo", " PROBLEMA")), "\n")
  cat("   pares con |r|>0.5:", sum(abs(R) > 0.5, na.rm = TRUE)/2, "\n\n")

  S <- cov(X, use = "pairwise.complete.obs")
  vp <- eigen(S)$values
  cond <- max(vp)/min(vp)
  cat("5. número de condición:", format(cond, digits = 3),
      ifelse(cond < 1000, " OK", ifelse(cond < 1e5, " revisar", " REDUNDANCIA")), "\n")
  if (cond >= 1000) {
    R2 <- abs(cor(X, use = "pairwise.complete.obs")); diag(R2) <- 0
    par <- which(R2 > 0.95, arr.ind = TRUE)
    if (nrow(par) > 0) {
      cat("   pares casi idénticos:\n")
      for (i in seq_len(nrow(par))) if (par[i,1] < par[i,2])
        cat("    ", names(X)[par[i,1]], "<->", names(X)[par[i,2]], "\n")
    }
  }
  invisible(NULL)
}

revisar("su_archivo.csv")
```

Si alguna columna hay que excluir:

``` r
revisar("su_archivo.csv", quitar = c("id", "anio", "total_general"))
```

------------------------------------------------------------------------

## Qué llevar el sábado

1.  El archivo **cargado en RStudio** y corriendo, no en el correo.
2.  La lista de **cuáles columnas numéricas van a usar** — ya sin ids, años ni códigos.
3.  La salida de `revisar()` pegada en un documento. **Si algo salió en rojo, llévelo igual**: se resuelve en clase, y llegar con el problema detectado vale más que llegar sin haberlo mirado.

> **Nadie se queda por fuera por un dataset con problemas.** Lo que sí cuesta es llegar sin haberlo revisado — porque entonces el problema aparece a mitad del Taller 2, cuando ya no hay tiempo.

------------------------------------------------------------------------

## Nota

Esta función **no se pudo ejecutar al escribir el checklist**. Si les da un error, avisen por WhatsApp y se corrige el mismo día. Nadie pierde puntos por un error del enunciado.
