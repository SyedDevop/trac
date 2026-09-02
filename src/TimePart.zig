const std = @import("std");
pub const Month = std.time.epoch.Month;

const TimePart = @This();

year: u16,
month: Month,
day: u5,
hour: u5,
min: u6,
sec: u6,
msec: u16,

pub fn now(io: std.Io) !TimePart {
    return fromTimeStamp(std.Io.Clock.now(.real, io));
}

pub fn fromTimeStamp(timestamp: std.Io.Timestamp) TimePart {
    const secs: u64 = @intCast(timestamp.toSeconds());
    const msec: i64 = @rem(timestamp.toMilliseconds(), 1000);
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = secs };

    const days_secs = epoch_secs.getDaySeconds();
    const hr = days_secs.getHoursIntoDay();
    const min = days_secs.getMinutesIntoHour();
    const sec = days_secs.getSecondsIntoMinute();

    const epoch_day = epoch_secs.getEpochDay();
    const epoch_year = epoch_day.calculateYearDay();
    const epoch_month = epoch_year.calculateMonthDay();

    return TimePart{
        .year = epoch_year.year,
        .month = epoch_month.month,
        .day = epoch_month.day_index + 1,
        .hour = hr,
        .min = min,
        .sec = sec,
        .msec = @intCast(msec),
    };
}

pub fn format(self: TimePart, writer: *std.Io.Writer) !void {
    try writer.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{
        self.year, self.month, self.day,
        self.hour, self.min,   self.sec,
        self.msec,
    });
}
