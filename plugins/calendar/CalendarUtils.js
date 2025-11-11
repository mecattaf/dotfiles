.pragma library

function localeFirstDay(locale) {
    if (!locale) {
        locale = Qt.locale()
    }
    const qtDay = locale.firstDayOfWeek // Qt.DayOfWeek enum (1=Monday ... 7=Sunday)
    return qtDay % 7 // convert to JS day index (0=Sunday, 1=Monday, ...)
}

function addDays(date, days) {
    const result = new Date(date)
    result.setDate(result.getDate() + days)
    return result
}

function addMonths(date, months) {
    const result = new Date(date)
    const day = result.getDate()
    result.setDate(1)
    result.setMonth(result.getMonth() + months)
    const month = result.getMonth()
    // Restore day but clamp to last day of month
    result.setDate(Math.min(day, daysInMonth(month, result.getFullYear())))
    return result
}

function startOfMonth(date) {
    return new Date(date.getFullYear(), date.getMonth(), 1)
}

function startOfWeek(date, firstDay) {
    const jsFirstDay = typeof firstDay === "number" ? firstDay : localeFirstDay()
    const result = new Date(date)
    const current = result.getDay()
    const diff = (current - jsFirstDay + 7) % 7
    result.setDate(result.getDate() - diff)
    return new Date(result.getFullYear(), result.getMonth(), result.getDate())
}

function isSameDay(a, b) {
    return a.getFullYear() === b.getFullYear() &&
        a.getMonth() === b.getMonth() &&
        a.getDate() === b.getDate()
}

function daysInMonth(monthIndex, year) {
    return new Date(year, monthIndex + 1, 0).getDate()
}

function weekdayLabels(locale, firstDay) {
    const jsFirstDay = typeof firstDay === "number" ? firstDay : localeFirstDay(locale)
    const labels = []
    for (let i = 0; i < 7; i++) {
        const dayIndex = (jsFirstDay + i) % 7
        // 2024-01-01 is a Monday; adjust using offset to map to Qt formatter
        const reference = new Date(2023, 11, 31 + dayIndex)
        labels.push(Qt.formatDate(reference, "ddd"))
    }
    return labels
}

function monthCells(monthDate, firstDay, today) {
    const jsFirstDay = typeof firstDay === "number" ? firstDay : localeFirstDay()
    const referenceToday = today || new Date()
    const startMonth = startOfMonth(monthDate)
    const month = startMonth.getMonth()
    const firstGridDateOffset = (startMonth.getDay() - jsFirstDay + 7) % 7
    const gridStart = addDays(startMonth, -firstGridDateOffset)

    const cells = []
    for (let index = 0; index < 42; index++) {
        const cellDate = addDays(gridStart, index)
        cells.push({
            day: cellDate.getDate(),
            date: cellDate,
            inMonth: cellDate.getMonth() === month,
            isToday: isSameDay(cellDate, referenceToday)
        })
    }
    return cells
}

function weekCells(weekStartDate, today, referenceMonth) {
    const referenceToday = today || new Date()
    const cells = []
    for (let i = 0; i < 7; i++) {
        const cellDate = addDays(weekStartDate, i)
        cells.push({
            day: cellDate.getDate(),
            date: cellDate,
            inMonth: typeof referenceMonth === "number" ? (cellDate.getMonth() === referenceMonth) : true,
            isToday: isSameDay(cellDate, referenceToday)
        })
    }
    return cells
}

function formatMonthYear(date, locale) {
    return Qt.formatDate(date, "MMMM yyyy")
}

function formatWeekRange(weekStartDate, locale) {
    const weekEnd = addDays(weekStartDate, 6)
    if (weekStartDate.getFullYear() === weekEnd.getFullYear()) {
        if (weekStartDate.getMonth() === weekEnd.getMonth()) {
            return Qt.formatDate(weekStartDate, "MMMM d") + " – " + Qt.formatDate(weekEnd, "d, yyyy")
        }
        return Qt.formatDate(weekStartDate, "MMM d") + " – " + Qt.formatDate(weekEnd, "MMM d, yyyy")
    }
    return Qt.formatDate(weekStartDate, "MMM d, yyyy") + " – " + Qt.formatDate(weekEnd, "MMM d, yyyy")
}

function isoWeekNumber(date, firstDay) {
    const jsFirstDay = typeof firstDay === "number" ? firstDay : localeFirstDay()
    const start = startOfWeek(date, jsFirstDay)
    const yearStart = startOfWeek(new Date(date.getFullYear(), 0, 4), jsFirstDay)
    const diff = start - yearStart
    return 1 + Math.round(diff / (7 * 24 * 60 * 60 * 1000))
}

function normalizeDate(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}


