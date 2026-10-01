import SpriteKit

/// The physics of the crate: tomatoes drop in, bounce and settle. The scene is transparent; the wooden crate is drawn around it.
@MainActor
final class CrateScene: SKScene {
    private let textures = TomatoTextures()
    private var nodes: [UUID: SKSpriteNode] = [:]
    private var current: [CrateTomato] = []
    private var highlighted: String?
    private let walls = SKNode()

    /// With Reduce Motion the tomatoes lie still where they would end up, with no bodies and no falling.
    var reduceMotion = false {
        didSet { if oldValue != reduceMotion { respawn() } }
    }

    var tomatoNodeCount: Int { nodes.count }
    var highlightedCount: Int { nodes.values.filter { $0.childNode(withName: "ring") != nil }.count }
    var dynamicBodyCount: Int { nodes.values.filter { $0.physicsBody?.isDynamic == true }.count }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        physicsWorld.gravity = CGVector(dx: 0, dy: -12)
        addChild(walls)
        rebuildWalls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildWalls()
        if size != oldSize { respawn() }
    }

    /// Shows `tomatoes` (oldest first) and rings the ones of the day `highlight`. New ones drop in;
    /// ones that are gone are removed. The first fill drops the tomatoes one after another.
    func update(_ tomatoes: [CrateTomato], highlight: String?) {
        current = tomatoes
        highlighted = highlight
        guard size.width > 1, size.height > 1 else { return }

        let initialFill = nodes.isEmpty
        let ids = Set(tomatoes.map(\.id))
        for (id, node) in nodes where !ids.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
        let diameter = CrateGeometry.baseDiameter(forCount: tomatoes.count)
        for tomato in tomatoes {
            if let node = nodes[tomato.id] { resize(node, growth: tomato.growth, diameter: diameter) }
        }
        let fresh = tomatoes.enumerated().filter { nodes[$0.element.id] == nil }
        let spacing = min(0.04, 2.5 / Double(max(fresh.count, 1)))
        for (order, entry) in fresh.enumerated() {
            spawn(entry.element, index: entry.offset, diameter: diameter, delay: initialFill ? Double(order) * spacing : 0)
        }
        refreshHighlight()
    }

    // MARK: Building

    private func respawn() {
        for node in nodes.values { node.removeFromParent() }
        nodes = [:]
        update(current, highlight: highlighted)
    }

    private func rebuildWalls() {
        let interior = CrateGeometry.interior(in: size)
        guard interior.width > 0 else {
            walls.physicsBody = nil
            return
        }
        let top = size.height * 3                                   // tall walls: tomatoes never fall out sideways
        let path = CGMutablePath()
        path.move(to: CGPoint(x: interior.minX, y: top))
        path.addLine(to: CGPoint(x: interior.minX, y: interior.minY))
        path.addLine(to: CGPoint(x: interior.maxX, y: interior.minY))
        path.addLine(to: CGPoint(x: interior.maxX, y: top))
        walls.physicsBody = SKPhysicsBody(edgeChainFrom: path)
    }

    private func spawn(_ tomato: CrateTomato, index: Int, diameter: CGFloat, delay: TimeInterval) {
        let interior = CrateGeometry.interior(in: size)
        let node = SKSpriteNode(texture: textures.texture(growth: tomato.growth))
        nodes[tomato.id] = node
        resize(node, growth: tomato.growth, diameter: diameter)
        if reduceMotion {
            node.position = CrateGeometry.settledPosition(index: index, in: interior, diameter: diameter)
            addChild(node)
            return
        }
        node.position = CGPoint(
            x: CrateGeometry.dropX(for: tomato.id, in: interior, diameter: diameter),
            y: size.height + diameter * 2
        )
        node.zRotation = CGFloat(tomato.id.uuid.1) / 255 * .pi
        let drop = SKAction.run { [weak self, weak node] in
            guard let self, let node, node.parent == nil, self.nodes.values.contains(node) else { return }
            self.addChild(node)
        }
        run(.sequence([.wait(forDuration: delay), drop]))
    }

    private func resize(_ node: SKSpriteNode, growth: Double, diameter: CGFloat) {
        let side = diameter * CGFloat(TomatoLook(growth: growth).scale)
        node.size = CGSize(width: side, height: side)
        guard !reduceMotion else {
            node.physicsBody = nil
            return
        }
        let body = SKPhysicsBody(circleOfRadius: side * 0.46)
        body.restitution = 0.35
        body.friction = 0.4
        body.angularDamping = 0.4
        node.physicsBody = body
    }

    private func refreshHighlight() {
        for tomato in current {
            guard let node = nodes[tomato.id] else { continue }
            let want = highlighted != nil && tomato.dayID == highlighted
            let ring = node.childNode(withName: "ring")
            if want, ring == nil {
                let shape = SKShapeNode(circleOfRadius: node.size.width * 0.55)
                shape.name = "ring"
                shape.strokeColor = .systemYellow
                shape.lineWidth = 2.5
                shape.fillColor = .clear
                shape.glowWidth = 2
                node.addChild(shape)
                node.zPosition = 1
            } else if !want, let ring {
                ring.removeFromParent()
                node.zPosition = 0
            }
        }
    }
}
