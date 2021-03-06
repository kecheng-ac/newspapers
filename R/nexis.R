#' Extract texts and meta data from Nexis HTML files
#'
#' This extract headings, body texts and meta data (date, byline, length,
#' secotion, edntion) from items in HTML files downloaded by the scraper.
#' @param path either path to a HTML file or a directory that containe HTML files
#' @param paragraph_separator a character to sperarate paragrahphs in body texts.
#' @param language_date a character to specify langauge-dependent date format.
#' @param raw_date return date of publication without parsing if \code{TRUE}.
#' @import utils XML
#' @export
#' @examples
#' \dontrun{
#' irt <- import_nexis('testthat/data/nexis/irish-times_1995-06-12_0001.html')
#' afp <- import_nexis('testthat/data/nexis/afp_2013-03-12_0501.html')
#' gur <- import_nexis('testthat/data/nexis/guardian_1986-01-01_0001.html')
#' spg <- import_nexis('testthat/data/nexis/spiegel_2012-02-01_0001.html', language_date = 'german')
#' all <- import_nexis('testthat/data/nexis', raw_date = TRUE)
#' }
import_nexis <- function(path, paragraph_separator = '|', language_date = c('english', 'german'), raw_date = FALSE){

    language_date <- match.arg(language_date)

    if (dir.exists(path)) {
        dir <- path
        file <- list.files(dir, full.names = TRUE, recursive = TRUE)
        data <- data.frame()
        for(f in file){
            #print(file)
            if(stri_detect_regex(f, '\\.html$|\\.htm$|\\.xhtml$', ignore.case = TRUE)){
                data <- rbind(data, import_nexis_html(f, paragraph_separator, language_date, raw_date))
            }
        }
    } else if (file.exists(path)) {
        data <- import_nexis_html(path, paragraph_separator, language_date, raw_date)
    } else {
        stop(path, " does not exist")
    }
    return(data)
}

import_nexis_html <- function(file, paragraph_separator, language_date, raw_date){

    #Convert format
    cat('Reading', file, '\n')

    line <- readLines(file, warn = FALSE, encoding = "UTF-8")
    html <- paste0(fix_nexis_html(line), collapse = "\n")

    #Load as DOM object
    dom <- htmlParse(html, encoding = "UTF-8")
    data <- data.frame()
    for(doc in getNodeSet(dom, '//doc')){
        data <- rbind(data, extract_nexis_attrs(doc, paragraph_separator, language_date, raw_date))
    }
    colnames(data) <- c('pub', 'edition', 'date', 'byline', 'length', 'section', 'head', 'body')
    data$file <- basename(file)

    return(data)
}


extract_nexis_attrs <- function(node, paragraph_separator, language_date, raw_date) {

    attrs <- list(pub = '', edition = '', date = '', byline = '', length = '', section = '', head = '', body = '')

    if (language_date == 'german') {
        regex <- paste0(c('([0-9]{1,2})',
                          '[. ]+(Januar|Februar|März|Maerz|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)',
                          '[ ]+([0-9]{4})',
                          '([ ]+(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag))?',
                          '([, ]+(.+))?'), collapse = '')
    } else {
        regex <- paste0(c('(January|February|March|April|May|June|July|August|September|October|November|December)',
                          '[, ]+([0-9]{1,2})',
                          '[, ]+([0-9]{4})',
                          '([,; ]+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))?',
                          '([, ]+(.+))?'), collapse = '')
    }

    n_max <- 0;
    i <- 1
    #print(node)
    for(div in getNodeSet(node, './/div')){

        str <- xmlValue(div, './/text()')
        str <- clean_text(str)
        n <- stri_length(str);
        if (is.na(n)) next

        #cat('----------------\n')
        #cat(i, stri_trim(s), "\n")

        if (i == 2) {
            attrs$pub <- stri_trim(str)
        } else if (i == 3) {
            if (raw_date) {
                attrs$date <- stri_trim(str)
            } else {
                m <- stri_match_first_regex(str, regex)
                if (all(!is.na(m[1,2:4]))) {
                    date <- paste0(m[1,2:4], collapse = ' ')
                    if (language_date == 'german') {
                        datetime <- stri_datetime_parse(date, 'd MMMM Y', locale = 'de_DE')
                    } else {
                        datetime <- stri_datetime_parse(date, 'MMMM d Y', locale = 'en_EN')
                    }
                    attrs$date <- stri_datetime_format(datetime, 'yyyy-MM-dd')
                }
                if (!is.na(m[1,8])) {
                    attrs$edition <- stri_trim(m[1,8])
                }
            }
        } else if (i == 4) {
            attrs$head <- stri_trim(str)
        } else if (i >= 5) {
            if (stri_detect_regex(str, "^BYLINE: ")) {
                attrs$byline = stri_trim(stri_replace_first_regex(str, "^BYLINE: ", ''))
            } else if (stri_detect_regex(str, "^SECTION: ")) {
                attrs$section = stri_trim(stri_replace_first_regex(str, "^SECTION: ", ''));
            } else if (stri_detect_regex(str, "^LENGTH: ")) {
                attrs$length = stri_trim(stri_replace_all_regex(str, "[^0-9]", ''))
            } else if (!is.null(attrs$length) && n > n_max &&
                       !stri_detect_regex(str, "^(BYLINE|URL|LOAD-DATE|LANGUAGE|GRAPHIC|PUBLICATION-TYPE|JOURNAL-CODE): ")){
                ps <- getNodeSet(div, './/p')
                p <- sapply(ps, xmlValue)
                attrs$body <- stri_trim(paste0(p, collapse = paste0(' ', paragraph_separator, ' ')))
                n_max = n
            }
        }
        i <- i + 1
    }
    if (attrs$pub[1] == '' || is.na(attrs$pub[1])) warning('Failed to extract publication name')
    if (attrs$date[1] == '' || is.na(attrs$date[1])) warning('Failed to extract date')
    if (attrs$head[1] == '' || is.na(attrs$head[1])) warning('Failed to extract heading')
    if (attrs$body[1] == '' || is.na(attrs$body[1])) warning('Failed to extract body text')
    return(as.data.frame(attrs, stringsAsFactors = FALSE))
}


fix_nexis_html <- function(line){
    d <- 0
    for (i in seq_along(line)) {
        l <- line[i]
        if (stri_detect_fixed(l, '<DOC NUMBER=1>')) d <- d + 1
        l = stri_replace_all_fixed(l, '<!-- Hide XML section from browser', '');
        l = stri_replace_all_fixed(l, '<DOC NUMBER=1>', paste0('<DOC ID="doc_id_',  d,  '">', collapse = ''))
        l = stri_replace_all_fixed(l, '<DOCFULL> -->', '<DOCFULL>');
        l = stri_replace_all_fixed(l, '</DOC> -->', '</DOC>');
        l = stri_replace_all_fixed(l, '<BR>', '<BR> ');
        line[i] <- l
    }
    return(line)
}

