---
title: "Parity fixture"
lang: es
number-sections: true
bibliography: sources.bib
cover:
  logo: logo.png
  header: Escuela de Ingeniería
  kind: Informe de avance
  fields:
    - Curso: Matemática Discreta
    - Docente: Ana Pérez
  people:
    columns: [Alumno, Código]
    rows:
      - [Luis Soto, U2025001]
  footer: Lima, 2026
---

# Introducción

Contar bien exige método [@rosen2019; @grimaldi1998]. Texto con *cursiva*, **negrita** y una fórmula en línea
$P(n, r) = \frac{n!}{(n-r)!}$ dentro del párrafo.

## Fórmulas de bloque

$$
\binom{12}{5} - \binom{9}{5} = 666
$$

## Tablas

: Conceptos y notación. {#tbl:conceptos}

| Concepto    | Notación        | En palabras                    |
|:------------|:---------------:|:-------------------------------|
| Permutación | $P(n,r)$        | Ordenaciones de r entre n.     |
| Combinación | $\binom{n}{r}$  | Subconjuntos de r entre n.     |

## Figuras

![Triángulo de Pascal en SVG.](pascal.svg){#fig:pascal width=40%}

Ver @fig:pascal y @tbl:conceptos.

## Listas

1. Resolver cuatro problemas de conteo.
2. Verificar cada resultado enumerando los casos.

# Fuentes

::: {#refs}
:::
