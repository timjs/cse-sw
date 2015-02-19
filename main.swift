import Foundation

// MARK: Extensions

extension Character {
    
	static let letters: ClosedInterval<Character> = "A"..."z"

    static func isLetter(char: Character) -> Bool {
        return letters.contains(char)
    }
    
}

extension String {

	func trim() -> String {
		return self.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet())
	}

	func splitLines() -> [String] {
		return self.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
	}

}

extension NSFileHandle {

	func read() -> String? {
		let data = self.readDataToEndOfFile()
		return NSString(data: data, encoding: NSUTF8StringEncoding) as? String
	}

	func readLines() -> [String] {
		if let string = self.read() {
			return string.trim().splitLines()
		} else {
			return []
		}
	}

}

let stdin = NSFileHandle.fileHandleWithStandardInput()

final class Box<T> {
	var unbox: T // XXX has to be var to mutate underlying Expr
	init(_ value: T) { self.unbox = value }
}

// MARK: Expressions

// @derive(Equatable, Hashable)
enum Expr {
	case App(Name, Box<Expr>, Box<Expr>)
	case Var(Name)
	case Sub(Repl)
}

typealias Name = String
typealias Repl = Int

extension Expr: Equatable {}
func == (lhs: Expr, rhs: Expr) -> Bool {
	switch lhs {
	case let .App(n1, l1, r1):
		switch rhs {
		case let .App(n2, l2, r2):
			return n1 == n2 && l1.unbox == l2.unbox && r1.unbox == r2.unbox
		default:
			return false
		}
		case let .Var(n1):
			switch rhs {
			case let .Var(n2):
				return n1 == n2
			default:
				return false
			}
			case let .Sub(i1):
				switch rhs {
				case let .Sub(i2):
					return i1 == i2
				default:
					return false
				}
	}
}

extension Expr: Hashable {
	var hashValue: Int {
		switch self {
		case let .App(n, l, r):
			return n.hashValue &+ l.unbox.hashValue &+ r.unbox.hashValue // FIXME: not good hashing
		case let .Var(n):
			return n.hashValue
		case let .Sub(i):
			return i.hashValue
		}
	}
}

extension Expr: Printable {
	var description: String {
		switch self {
		case let .App(n, l, r):
			return n + "(" + l.unbox.description + "," + r.unbox.description + ")"
		case let .Var(n):
			return n
		case let .Sub(i):
			return i.description
		}
	}
}

// MARK: Parser

struct Parser {
	var generator: IndexingGenerator<String>

	init(_ string: String) {
		self.generator = string.generate()
	}

	private func peek() -> Character? {
		var copy = generator
		return copy.next()
	}

	private mutating func next() -> Character? {
		return generator.next()
	}

	mutating func nextWhile(predicate: Character -> Bool) -> String {
		var result = ""
		while let char = peek() {
			if predicate(char) {
				result.append(char)
				next()
			} else {
				break
			}
		}
		return result
	}

	mutating func parseName() -> Name {
		return nextWhile(Character.isLetter)
	}

	func parseVar(name: Name) -> Expr {
		return .Var(name)
	}

	mutating func parseApp(name: Name) -> Expr {
		next()
		let left = parseExpr()
		next()
		let right = parseExpr()
		next()
		return .App(name, Box(left), Box(right))
	}

	mutating func parseExpr() -> Expr {
		let name = parseName()
		switch peek() {
		case .Some("("):
			return parseApp(name)
		default:
			return parseVar(name)
		}
	}

	mutating func parse() -> Expr {
		return parseExpr()
	}

}

// MARK: Elimination

struct State {
	var map: [Expr:Repl]
	var num: Repl
}

extension Expr {

	func cse(inout state: State) -> Expr {
		if let repl = state.map[self] {
			return .Sub(repl)
		} else {
			state.map[self] = state.num
			state.num++
			switch self {
			case let .App(n, l, r):
				let l_ = l.unbox.cse(&state)
				let r_ = r.unbox.cse(&state)
				return .App(n, Box(l_), Box(r_))
			case let .Var(n):
				return .Var(n)
			case let .Sub(i):
				fatalError("Expr.Sub can't be in this expression tree")
			}
		}
	}

}

// MARK: Main

var lines = stdin.readLines().generate()
let lineCount = lines.next()!.toInt()!
for line in lines {
	var parser = Parser(line)
	var expr = parser.parse()
	var state = State(map: [:], num: 1)
	expr = expr.cse(&state)
	println(expr)
}

