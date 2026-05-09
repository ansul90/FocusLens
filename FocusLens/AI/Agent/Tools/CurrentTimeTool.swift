import Foundation

struct CurrentTimeTool: AgentTool {
    let name = "current_time"
    let description = "Returns the current date and time, plus convenient labels like today and yesterday. Call this first when the user's question involves relative dates."
    let argsDescription = "none"

    func run(args: [String: Any]) async -> String {
        let now = Date()
        let cal = Calendar.current
        let fmt = DateUtils.dayFormatter()
        let today = fmt.string(from: now)
        let yesterday = fmt.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
        let weekAgo = fmt.string(from: cal.date(byAdding: .day, value: -7, to: now)!)

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "yyyy-MM-dd HH:mm"
        timeFmt.timeZone = TimeZone.current

        struct Out: Encodable {
            let now: String
            let today: String
            let yesterday: String
            let week_ago: String
            let timezone: String
        }
        return toolJSON(Out(
            now: timeFmt.string(from: now),
            today: today,
            yesterday: yesterday,
            week_ago: weekAgo,
            timezone: TimeZone.current.identifier
        ))
    }
}
