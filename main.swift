import Foundation

// MARK: Extensions

func decurry<A,B>(f: A -> () -> B) -> A -> B {
    return { a in f(a)() }
}

extension Character {
    
	static let letters: ClosedInterval<Character> = "A"..."z"

	func isLetter() -> Bool {
		return Character.letters.contains(self)
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
	let unbox: T
	init(_ value: T) { self.unbox = value }
}

struct PeekableGenerator<S: SequenceType>: GeneratorType {
	var generator: S.Generator
	var peeked: S.Generator.Element?

	init<T: SequenceType where T.Generator == S.Generator>(_ sequence: T) {
		generator = sequence.generate()
		peeked = nil
	}

	mutating func next() -> S.Generator.Element? {
		if let current = peeked {
			peeked = nil
			return current
		} else {
			return generator.next()
		}
	}

	mutating func peek() -> S.Generator.Element? {
		if let current = peeked {
			return current
		} else {
			peeked = generator.next()
			return peeked
		}
	}

}

// MARK: Expressions

// @derive(Equatable)
enum Expr {
	case App(Hash, Name, Box<Expr>, Box<Expr>)
	case Var(Hash, Name)
	case Sub(Repl)
}

typealias Hash = Int
typealias Name = String
typealias Repl = Int

extension Expr: Printable {

	var description: String {
		switch self {
		case let .App(_, n, l, r):
			return "\(n)(\(l.unbox.description),\(r.unbox.description))"
		case let .Var(_, n):
			return n//.description
		case let .Sub(i):
			return i.description
		}
	}

}

extension Expr: Hashable {

	var hashValue: Int {
		switch self {
		case let .App(h, _, _, _):
			return h
		case let .Var(h, _):
			return h
		case let .Sub(i):
			return i
		}
	}

}

// MARK: Boilerplate

extension Expr: Equatable {}
func == (lhs: Expr, rhs: Expr) -> Bool {
	switch lhs {
	case let .App(_, n1, l1, r1):
		switch rhs {
		case let .App(_, n2, l2, r2):
			return n1 == n2 && l1.unbox == l2.unbox && r1.unbox == r2.unbox
		default:
			return false
		}
	case let .Var(_, n1):
		switch rhs {
		case let .Var(_, n2):
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

// MARK: Parser

struct Parser {
	var input: PeekableGenerator<String>

	init(_ string: String) {
		input = PeekableGenerator(string)
	}

	mutating func parseWhile(predicate: Character -> Bool) -> String {
		var result = ""
		while let char = input.peek() {
			if predicate(char) {
				result.append(char)
				input.next()
			} else {
				break
			}
		}
		return result
	}

}

extension Parser {

	mutating func parseName() -> Name {
		return parseWhile(decurry(Character.isLetter))
	}

	func parseVar(name: Name) -> Expr {
		let hash = name.hashValue
		return .Var(hash, name)
	}

	mutating func parseApp(name: Name) -> Expr {
		input.next()
		let left = parseExpr()
		input.next()
		let right = parseExpr()
		input.next()
		let hash = name.hashValue &+ left.hashValue &+ right.hashValue
		return .App(hash, name, Box(left), Box(right))
	}

	mutating func parseExpr() -> Expr {
		let name = parseName()
		switch input.peek() {
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

	init() {
		map = [:]
		num = 1
	}

}

extension Expr {

	func cse(inout state: State) -> Expr {
		if let repl = state.map[self] {
			return .Sub(repl)
		} else {
			state.map[self] = state.num
			state.num += 1
			switch self {
			case let .App(h, n, l, r):
				let l_ = l.unbox.cse(&state)
				let r_ = r.unbox.cse(&state)
				return .App(h, n, Box(l_), Box(r_))
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
lines.next() // lineCount

for line in lines {
	var parser = Parser(line)
	let expr = parser.parse()
	var state = State()
	let result = expr.cse(&state)
	println(result)
}

