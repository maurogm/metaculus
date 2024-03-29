#' ---
#' title: "Metaculus Beginners on Points Leaderboard"
#' subtitle: "How many beginners will be in the top 20 of the Point Rankings for Questions Opened in the Last 30 Days on February 28?"
#' author: maurogm
#' date: "`r Sys.Date()`"
#' output:
#'   github_document:
#'     toc: true
#'     toc_depth: 2
#'     number_sections: false
#'     fig_width: 10
#'     fig_height: 7
#'     dev: svg
#'     df_print: default
#'     hard_line_breaks: true
#'     html_preview: true
#' ---



#+ r knitr-global-options, include = FALSE
knitr::opts_chunk$set(
    warning = FALSE, message = FALSE, verbose = TRUE,
    fig.show = "hold", fig.height = 7, fig.width = 10
)
knitr::opts_knit$set(
    root.dir = normalizePath(".")
)

# rmarkdown::render("R/tournaments/beginner_2023Q1/13_beginners_in_leaderboard.R")


#' # Preparation
#'
#' ## Load libraries
library(data.table)
library(magrittr)
library(dplyr)
library(ggplot2)
library(tidyverse)
library(readxl)
library(ggrepel)


#' ## Define paths
PATH_DATA_DIR <- "data/tournaments/beginner_2023Q1"
PATH_TOURNAMENT_LEADERBOARD <- glue::glue("{PATH_DATA_DIR}/beginner_tournament_leaderboard.xls")
PATH_RANKING_30_DAYS <- glue::glue("{PATH_DATA_DIR}/metaculus_ranking_30_days.xls")
PATH_RANKING_90_DAYS <- glue::glue("{PATH_DATA_DIR}/metaculus_ranking_90_days.xls")

date_labels <- tribble(
    ~date, ~label,
    "2023-02-07", "Initial meassurement",
    "2023-02-08", "Yoga W02 resolution",
    "2023-02-12", "Club World Cup resolution",
    "2023-02-13", "Book ratings expiring",
    "2023-02-14", "ALOS-3 resolution",
    "2023-02-15", "Yoga W03 resolution",
    "2023-02-18", "Building permits resolution",
    "2023-02-19", "Bakhmut expiring",
    "2023-02-20", "Influenza & Doomsday expiring",
    "2023-02-27", "Yoga & Snow expiring",
) %>%
    mutate(label = ordered(label, levels = label))
dates_with_points_relevant_for_resolution <- date_labels[c(3, 5, 7), ]

#' ## Define functions
#'
#' #### Data wrangling functions
extract_level <- function(vec) stringr::str_extract(vec, "[0-9]+") %>% as.integer()
truncate_level <- function(level, bound = 5) ifelse(as.numeric(level) > bound, "6+", level)
read_ranking <- function(path, sheet_name, leaderboard_type) {
    df <- read_excel(path, sheet = sheet_name)
    add_suffix <- function(colname) paste0(colname, "_", leaderboard_type)
    df %>%
        mutate(level = extract_level(Level)) %>%
        mutate(date = sheet_name) %>%
        select(date, User, level, Rank, Points) %>%
        setnames(c("date", "user", "level", add_suffix("rank"), add_suffix("points")))
}
read_tournament_leaderboard <- function(path, sheet_name, leaderboard_type = "tournament") {
    extract_denominators <- function(v) {
        stringr::str_extract(v, "/[0-9]+") %>%
            stringr::str_replace("/", "")
    }
    extract_numerators <- function(v) {
        stringr::str_extract(v, "[0-9]+/") %>%
            stringr::str_replace("/", "")
    }

    df <- read_excel(path, sheet = sheet_name)
    df %>%
        mutate(
            date = sheet_name,
            answered = as.integer(extract_numerators(Completion)),
            total = as.integer(extract_denominators(Completion)),
            completion = answered / total,
            coverage = as.numeric(stringr::str_remove(Coverage, "%")) / 100
        ) %>%
        select(
            date,
            user = Forecaster,
            rank = Rank,
            take = Take,
            score = Score,
            coverage,
            completion,
            answered,
            total,
        ) %>%
        setnames(old = c("rank"), new = c(paste0("rank_", leaderboard_type)))
}

read_all_sheets <- function(path_to_file, read_function, leaderboard_type) {
    readxl::excel_sheets(path_to_file) %>%
        map(
            ~ read_function(path_to_file, ., leaderboard_type)
        ) %>%
        rbindlist()
}

#' #### Data viz functions
apply_theme <- function() {
    theme_minimal() +
        theme(
            legend.position = "bottom",
            legend.text = element_text(size = 10),
            legend.key.size = unit(0.5, "cm"),
            plot.title = element_text(size = 14, hjust = 0.5),
            plot.subtitle = element_text(size = 12, hjust = 0.5),
            axis.title = element_text(size = 12),
            axis.text = element_text(size = 10),
            # panel.background = element_rect(fill = "white", color = "black"),
            # panel.border = element_rect(fill = NA, color = "black"),
            # give very light gray background to the plot area, with no box border:
            panel.background = element_rect(fill = "#F0F0F0", color = NA),
            panel.grid.major = element_line(color = "#F5F5F5"),
            panel.grid.minor = element_line(color = "#F7F7F7"),
            plot.margin = unit(c(0.5, 0.5, 0.5, 0.5), "cm")
        )
}

trunc_level_color_scale <- function() {
    scale_color_manual(
        values = c("#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#a65628"),
        breaks = c("1", "2", "3", "4", "5", "6+"),
    )
}

#' Source utils:
source("R/utils/metaculus.R")



#' ## Data preparation
#'
#' ### Read and wrangle data
tournament_leaderbord <- read_all_sheets(path_to_file = PATH_TOURNAMENT_LEADERBOARD, read_function = read_tournament_leaderboard, leaderboard_type = "tournament")
df_30_days <- read_all_sheets(PATH_RANKING_30_DAYS, read_ranking, "30_days") %>%
    mutate(is_top_20 = rank_30_days <= 20)
df_90_days <- read_all_sheets(PATH_RANKING_90_DAYS, read_ranking, "90_days")

df_joined <- df_30_days %>%
    merge(df_90_days, by = c("date", "user", "level"), all = TRUE) %>%
    merge(tournament_leaderbord, by = c("date", "user"), all = TRUE) %>%
    merge(date_labels, "date")

df_current <- df_joined[date == max(date)]

current_point_cutoff_30 <- df_current[
    rank_30_days %in% c(20, 21),
    median(points_30_days)
]
current_point_cutoff_90 <- df_current[
    rank_90_days %in% c(20, 21),
    median(points_90_days)
]

#' # Exploration
#'
#' ## User evolution

#+ tournament-score-evolution, fig.height=10
top_score <- max(df_joined$score, na.rm = TRUE)
df_joined %>%
    arrange(date) %>%
    setDT() %>%
    .[, delta := score - lag(score), user] %>%
    .[, is_active := any(delta != 0, na.rm = TRUE), user] %>%
    .[!str_ends(label, "expiring")] %>% 
    mutate(level = truncate_level(level)) %>%
    ggplot(aes(x = date, y = score)) +
    geom_point(aes(shape = is_top_20)) +
    geom_path(aes(group = user), # arrows where score didn't change
        data = ~ filter(., !is_active),
        alpha = 0.2,
        linetype = "dotted",
        arrow = arrow(length = unit(4, "mm"), ends = "last")
    ) +
    geom_path(aes(group = user, color = level), # arrows where score did change
        data = ~ filter(., is_active),
        arrow = arrow(length = unit(4, "mm"), ends = "last")
    ) +
    ggrepel::geom_text_repel(aes(label = user, color = level),
        data = filter(df_current, is_top_20) %>%
            mutate(level = truncate_level(level)),
        nudge_x = 0.15
    ) +
    geom_label(
        data = filter(date_labels, !str_ends(label, "expiring")), aes(x = date, label = label), y = top_score + 0.1,
        size = 3, angle = 25, color = "black", fill = "white", alpha = 0.8
    ) +
    labs(
        title = "Evolution of tournament scores",
        caption = "(Only users currently in the top 20 of the 30-day leaderboard are labeled)",
        x = "Date",
        y = "Tournament Score",
        shape = "Is in top 20?",
        color = "Level: "
    ) +
    trunc_level_color_scale() +
    apply_theme()

#+ tournament-points-evolution, fig.height=10
df_joined %>%
    arrange(date) %>%
    setDT() %>%
    mutate(level = truncate_level(level)) %>%
    ggplot(aes(x = date, y = points_30_days)) +
    geom_point(aes(shape = is_top_20)) +
    geom_path(aes(group = user, color = level), alpha = 0.5,
        arrow = arrow(length = unit(4, "mm"), ends = "last")
    ) +
    ggrepel::geom_text_repel(aes(label = user, color = level),
        data = filter(df_current, is_top_20) %>%
            mutate(level = truncate_level(level)),
        nudge_x = 0.15
    ) +
    geom_label(
        data = date_labels, aes(x = date, label = label), y = top_score + 0.1,
        size = 3, angle = 25, color = "black", fill = "white", alpha = 0.8
    ) +
    labs(
        title = "Evolution of points in the last 30 days",
        caption = "(Only users currently in the top 20 of the 30-day leaderboard are labeled)",
        x = "Date",
        y = "Points",
        shape = "Is in top 20?",
        color = "Level: "
    ) +
    trunc_level_color_scale() +
    apply_theme()


#' ## User points
#'

#+ plot-points-30-vs-90-days
df_current %>%
    mutate(level = truncate_level(level)) %>%
    ggplot(aes(x = points_30_days, y = points_90_days, color = level)) +
    geom_text(aes(label = user), size = 3, angle = 25) +
    geom_vline(xintercept = current_point_cutoff_30, linetype = "dashed", alpha = 0.3) +
    geom_hline(yintercept = current_point_cutoff_90, linetype = "dashed", alpha = 0.3) +
    trunc_level_color_scale() +
    labs(
        title = "Users in the top 100 of both leaderboards",
        subtitle = "(dashed lines mark current top-20 thresholds)",
        x = "Points for questions opened in the last 30 days",
        y = "Points for questions opened in the last 90 days",
        color = "User Level: "
    ) +
    scale_x_log10() +
    scale_y_log10() +
    apply_theme()


#+ plot-rank-30-vs-rank-tournament
df_current %>%
    mutate(level = truncate_level(level)) %>%
    ggplot(aes(x = coverage, y = points_30_days, color = level)) +
    geom_text(aes(label = user), size = 3) +
    geom_hline(yintercept = current_point_cutoff_30, linetype = "dashed", alpha = 0.3) +
    trunc_level_color_scale() +
    labs(
        title = "Tournament coverage vs. points in the last 30 days",
        subtitle = "(dashed line marks current top-20 threshold)",
        x = "Tournament coverage",
        y = "Points for questions opened in the last 30 days",
        color = "User Level: "
    ) +
    apply_theme()



#' ### Correlations:
df_for_cor <- df_current %>%
    filter(!is.na(rank_30_days), !is.na(rank_tournament))

#' Spearman correlation with tournament rank:
cor(df_for_cor$rank_30_days, df_for_cor$rank_tournament, method = "spearman")

#' Spearman correlation with tournament coverage:
cor(df_for_cor$coverage, df_for_cor$rank_tournament, method = "spearman")


#' ### Delta score vs. delta points
#'
#' (At least for this selection of users) people tend to accumulate points
#' just by being active, even if they score negatively:
#+ plot-delta-score-vs-delta-points
df_joined %>%
    arrange(date) %>%
    setDT() %>%
    .[, delta_score := score - lag(score), user] %>%
    .[, delta_points := points_30_days - lag(points_30_days), user] %>%
    filter(delta_score != 0) %>%
    mutate(level = truncate_level(level)) %>%
    ggplot(aes(delta_score, delta_points, label = user, color = level)) +
    geom_text_repel(max.overlaps = 1000) +
    trunc_level_color_scale() +
    geom_hline(yintercept = 0, linetype = "dashed", alpha = 0.3) +
    geom_vline(xintercept = 0, linetype = "dashed", alpha = 0.3) +
    labs(
        title = "Change in tournament score vs. change in points",
        subtitle = "(only users who changed their scores are shown)",
        x = "Change in tournament score",
        y = "Change in points",
        color = "User Level: "
    ) +
    facet_grid(. ~ label) +
    apply_theme()


#' ## Recent performance
df_recency <- df_joined %>%
    .[, new_answers := max(answered) - min(answered), user] %>%
    .[, delta_answered := answered - lag(answered), user] %>%
    .[, delta_score := score - lag(score), user] %>%
    .[, delta_points_30 := points_30_days - lag(points_30_days), user] %>%
    .[, delta_coverage := coverage - lag(coverage), user]

#+ plot-new-answers-vs-points-30-days
df_joined %>%
    .[, new_answers := max(answered) - min(answered), user] %>%
    filter(new_answers > 0) %>%
    filter(date == max(date)) %>%
    mutate(level = truncate_level(level)) %>%
    mutate(count = 1) %>%
    ggplot(aes(points_30_days, new_answers, label = user, color = level)) +
    geom_text_repel(max.overlaps = 300) +
    trunc_level_color_scale() +
    labs(
        title = "New answers vs. points in the last 30 days",
        subtitle = "(only users who answered questions are shown)",
        x = "Points for questions opened in the last 30 days",
        y = "New answers",
        color = "User Level: "
    ) +
    apply_theme()

#' Current levels of people that answered questions since meassuring started:
df_joined %>%
    arrange(rank_30_days) %>%
    setDT() %>%
    .[, new_answers := max(answered) - min(answered), user] %>%
    # filter(is_top_20) %>%
    filter(date == max(date)) %>%
    arrange(rank_30_days) %>%
    filter(new_answers > 0)

#' ### Points that will be counted for ranking at resolution date
#' 
#' This is only an approximiation, since I can't account for the points that
#' expire each day after 30 days pass since their question was opened.

guaranteed_points <- df_recency %>%
    semi_join(dates_with_points_relevant_for_resolution) %>%
    group_by(user) %>%
    mutate(level = max(level)) %>%
    group_by(user, level) %>%
    summarise(guaranteed_points = sum(delta_points_30)) %>%
    filter(guaranteed_points != 0) %>%
    arrange(desc(guaranteed_points)) %>%
    mutate(is_beginner = level < 6) %>%
    setDT()

guaranteed_points %>%
    head(20)

guaranteed_points_threshold <- 20
guaranteed_points %>%
    .[guaranteed_points > guaranteed_points_threshold] %>%
    .[, mean(is_beginner)] * 20

#+ relevant-points, fig.height=8
guaranteed_points %>% 
    .[order(guaranteed_points)] %>% 
    .[, rank := 1:nrow(.)] %>% 
    mutate(level = truncate_level(level)) %>%
    ggplot(aes(guaranteed_points, rank, label = user, color = level)) +
    geom_text_repel(max.overlaps = 300) +
    trunc_level_color_scale() +
    scale_y_continuous(breaks = NULL, labels = NULL) +
    labs(
        title = "Points that will be counted for ranking at resolution date",
        subtitle = "(only users who changed their points by more than 5 are shown)",
        x = "Guaranteed points for question resolution",
        y = "",
        color = "User Level: "
    ) +
    apply_theme()

#' ### Points for Yoga question
df_recency %>%
    .[str_starts(label, "Yoga"), .(yoga_points = sum(delta_points_30)), user] %>%
    .[yoga_points != 0] %>% 
    .[order(-yoga_points)]

#' # Predicted leaderboard:
#'
#' #### High certainty:
#' Unwrapped (6+)
#' OldJohnL (6+)
#' MichaelSimm (3)
#' MayMeta (6+)
#' nataliem (3)
#' draaglom (3)
#'
#' #### Uncertain but maybe:
#' mart (1)
#' patricktnast (2)
#' skmmcj (3)
#'
#' #### Because they are active:
#' jagop (6+)
#'
#' #### Maybe:
#' m4ktub (3)
#'
#'
#' #### If they return to the tournament:
#' alix_ph (3)
#' plddp (5)
#' KROADER (4)
#'
#' #### If they keep predicting in the tournament:
#'
#' PepeS (6+)
#' geethepredictor (6+)
#' johnnycaffeine (6+)
#'
#' #### Taken out:
#'
#' puffymist (has not been predicting lately)
#' gak53 (2) -> No está muy activo, muchos puntos son por Yoga, y perdió 200 en el del ALOS-3
#' 
#' ### New predictions
#' 
#' #### Ayes:
#' 
#'  1:        OldJohnL     6               114       FALSE
#' 
#'  2:      OpenSystem    13                84       FALSE
#' 
#'  3:           jagop     6                82       FALSE
#' 
#'  4:          m4ktub     3                81        TRUE
#' 
#'  5:         MayMeta     8                77       FALSE
#' 
#'  6:   Unwrapped8600     7                77       FALSE
#' 
#'  7:     MichaelSimm     4                72        TRUE
#' 
#'  8:            Vang    38                67       FALSE
#' 
#' 12:        draaglom     4                43        TRUE
#' 
#' 15:    patricktnast     2                40        TRUE
#' 
#' 16:         alix_ph     3                35        TRUE
#' 
#' 18:        nataliem     3                31        TRUE
#' 
#' 19:           PepeS    39                30       FALSE
#' 
#' 20:      Rexracer63    23                28       FALSE
#' 
#' 22:          TheAGI     2                26        TRUE
#' 
#' nextbigfuture
#' 
#' dt15
#' 
#' johnnycaffeine
#' 

#' #### Maybes:
#' 
#' Sergio
#' 
#' rodeo_flagellum
#' 

#' #### Nays:
#' 
#' 25:        jiaodeng     2                18        TRUE
#' 
#'  9:     truegriffin     2                65        TRUE
#' 
#' 10:          hobson     4                63        TRUE
#' 
#' 11:        mdkenyon     4                45        TRUE
#' 
#' 13:           galen    35                43       FALSE
#' 
#' 14:           plddp     5                43        TRUE
#' 
#' 17:         phutson     2                32        TRUE
#' 
#' 21:            rgal     7                27       FALSE
#' 
#' 23:           edl41     1                21        TRUE
#' 
#' 24: rodeo_flagellum    26                20       FALSE
#' 




#' # Export table

df_joined %>%
    filter(date == max(date)) %>%
    select(user, level, rank_30_days, rank_90_days, points_30_days, points_90_days, rank_tournament, answered) %>%
    arrange(rank_30_days, rank_90_days, rank_tournament) %>%
    filter(!is.na(level)) %>%
    setDT() %>%
    .[level <= 5, user := glue::glue("**{user}**")] %>%
    export_markdown_table("beginers_current_data.txt")
