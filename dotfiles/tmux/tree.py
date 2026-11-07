#!/usr/bin/env python3
"""AeroSpace's move, join-with and flatten-workspace-tree for tmux panes.

    tree.py move left|down|up|right PANE
    tree.py join left|down|up|right PANE
    tree.py flatten PANE

Ports MoveCommand, JoinWithCommand and FlattenWorkspaceTreeCommand from
AeroSpace to the window's layout tree, then applies it with select-layout.
"""

import json
import shutil
import subprocess
import sys

TMUX = shutil.which("tmux") or "tmux"

# direction: (orientation of the axis, step along it)
DIRS = {"left": ("h", -1), "right": ("h", 1), "up": ("v", -1), "down": ("v", 1)}


def tmux(*args):
    return subprocess.run([TMUX, *args], capture_output=True, text=True)


class Node:
    def __init__(self, pane=None, orient=None):
        self.pane = pane  # "%3", or None for a container
        self.orient = orient  # "h" side by side, "v" stacked
        self.children: list[Node] = []
        self.parent: Node | None = None
        self.weight = 1.0  # share of the parent's length
        self.sx = self.sy = 0  # size, as parsed

    def leaves(self):
        if self.pane:
            return [self]
        return [leaf for c in self.children for leaf in c.leaves()]

    def index(self):
        assert self.parent
        return next(i for i, c in enumerate(self.parent.children) if c is self)


def detach(node):
    node.parent.children.pop(node.index())
    node.parent = None


def attach(node, parent, index, weight=None):
    """AeroSpace's bind(). weight=None is WEIGHT_AUTO: the siblings' average."""
    if node.parent:
        detach(node)
    kids = parent.children
    if weight is None:
        weight = sum(c.weight for c in kids) / len(kids) if kids else 1.0
    node.weight = weight
    node.parent = parent
    kids.insert(index, node)


def tidy(node):
    """Drop empty containers, flatten single-child ones, merge same-orientation nesting."""
    if node.pane:
        return node
    kids = []
    for child in node.children:
        child = tidy(child)
        if child is None:
            continue
        if not child.pane and child.orient == node.orient:
            total = sum(g.weight for g in child.children)
            for g in child.children:
                g.weight *= child.weight / total
                kids.append(g)
        else:
            kids.append(child)
    if not kids:
        return None
    if len(kids) == 1:
        kids[0].weight = node.weight
        kids[0].parent = node.parent
        return kids[0]
    node.children = kids
    for child in kids:
        child.parent = node
    return node


# --- AeroSpace commands ------------------------------------------------------


def move(root, pane, direction, mru):
    orient, step = DIRS[direction]
    parent = pane.parent
    if parent is None:
        return root
    j = pane.index() + step
    if parent.orient == orient and 0 <= j < len(parent.children):
        sibling = parent.children[j]
        if sibling.pane:
            attach(pane, parent, j, pane.weight)
        else:
            deep_move_in(pane, sibling, orient, mru)
        return root
    node = parent
    while node.parent and node.parent.orient != orient:
        node = node.parent
    if node.parent:
        attach(pane, node.parent, node.index() + (step > 0))
        return root
    # At the window edge: wrap the tree in a new container.
    new = Node(orient=orient)
    attach(root, new, 0)
    attach(pane, new, 1 if step > 0 else 0)
    return new


def deep_move_in(pane, container, orient, mru):
    target = container
    while not target.pane and target.orient != orient:
        target = mru(target)
    if target.pane:
        attach(pane, target.parent, target.index() + 1)
    else:
        attach(pane, target, 0)


def join(root, pane, direction):
    orient, step = DIRS[direction]
    node = pane
    while node.parent:
        parent = node.parent
        k = node.index() + step
        if parent.orient == orient and 0 <= k < len(parent.children):
            break
        node = parent
    else:
        return root
    target = parent.children[k]
    new = Node(orient="v" if orient == "h" else "h")
    weight = target.weight
    detach(target)
    attach(new, parent, k, weight)
    attach(target, new, 0)
    attach(pane, new, 0 if step > 0 else len(new.children))
    return root


def flatten(root):
    if root.pane:
        return root
    leaves = root.leaves()
    root.children = []
    for leaf in leaves:
        leaf.parent = None
        attach(leaf, root, len(root.children), 1.0)
    return root


# --- Layout strings ----------------------------------------------------------
#
# tmux 3.8 reports #{window_layout} as JSON ({"V":2,"L":{...}}); earlier
# versions use the checksummed "csum,WxH,X,Y{...}" string. Both are read.
# Layouts are always written in the old form, which 3.8's select-layout
# still accepts, so one dump() serves every tmux version.


def parse(layout):
    if layout.startswith("{"):
        return parse_json(json.loads(layout)["L"])
    return parse_string(layout)


def parse_json(cell):
    if cell["t"] == "p":
        node = Node(pane=cell["I"])
    else:
        node = Node(orient=cell["t"])
        for c in cell["c"]:
            child = parse_json(c)
            child.parent = node
            child.weight = child.sx if node.orient == "h" else child.sy
            node.children.append(child)
    node.sx, node.sy = cell["w"], cell["h"]
    return node


def parse_string(layout):
    s = layout.split(",", 1)[1]
    pos = 0

    def number():
        nonlocal pos
        start = pos
        while pos < len(s) and s[pos].isdigit():
            pos += 1
        return int(s[start:pos])

    def cell():
        nonlocal pos
        sx = number()
        pos += 1
        sy = number()
        pos += 1
        number()
        pos += 1
        number()
        if s[pos] in "{[":
            node = Node(orient="h" if s[pos] == "{" else "v")
            pos += 1
            while True:
                child = cell()
                child.parent = node
                child.weight = child.sx if node.orient == "h" else child.sy
                node.children.append(child)
                pos += 1
                if s[pos - 1] in "}]":
                    break
        else:
            pos += 1
            node = Node(pane="%" + str(number()))
        node.sx, node.sy = sx, sy
        return node

    return cell()


def min_len(node, orient):
    if node.pane:
        return 1
    lens = [min_len(c, orient) for c in node.children]
    return sum(lens) + len(lens) - 1 if node.orient == orient else max(lens)


def split(total, nodes, orient):
    """Share total cells by weight, keeping each node at or above its minimum."""
    mins = [min_len(n, orient) for n in nodes]
    wsum = sum(n.weight for n in nodes)
    exact = [total * n.weight / wsum for n in nodes]
    sizes = [max(m, int(e)) for m, e in zip(mins, exact)]
    idx = range(len(nodes))
    while sum(sizes) < total:
        sizes[max(idx, key=lambda i: exact[i] - sizes[i])] += 1
    while sum(sizes) > total:
        shrinkable = [i for i in idx if sizes[i] > mins[i]]
        sizes[max(shrinkable, key=lambda i: sizes[i] - exact[i])] -= 1
    return sizes


def dump(node, x, y, sx, sy):
    head = f"{sx}x{sy},{x},{y}"
    if node.pane:
        return f"{head},{node.pane[1:]}"
    h = node.orient == "h"
    sizes = split((sx if h else sy) - len(node.children) + 1, node.children, node.orient)
    parts = []
    for child, size in zip(node.children, sizes):
        if h:
            parts.append(dump(child, x, y, size, sy))
            x += size + 1
        else:
            parts.append(dump(child, x, y, sx, size))
            y += size + 1
    return head + ("{" if h else "[") + ",".join(parts) + ("}" if h else "]")


def checksum(body):
    csum = 0
    for ch in body:
        csum = (csum >> 1) + ((csum & 1) << 15)
        csum = (csum + ord(ch)) & 0xFFFF
    return f"{csum:04x}"


# --- Main --------------------------------------------------------------------


def main():
    op, args = sys.argv[1], sys.argv[2:]
    pane_id = args[-1]
    direction = args[0] if op != "flatten" else None

    layout = tmux("display", "-p", "-t", pane_id, "#{window_layout}").stdout.strip()
    parsed = parse(layout)
    sx, sy = parsed.sx, parsed.sy
    root = tidy(parsed)
    assert root
    before = dump(root, 0, 0, sx, sy)
    pane = next(leaf for leaf in root.leaves() if leaf.pane == pane_id)

    def mru(container):
        # AeroSpace picks the container's most recently focused child. tmux
        # resolves {left-of} etc. to the most recently focused neighbour.
        found = None
        if tmux("display", "-p", "#{pane_id}").stdout.strip() == pane_id:
            found = tmux("display", "-p", "-t", "{%s-of}" % direction, "#{pane_id}").stdout.strip()
        for child in container.children:
            if any(leaf.pane == found for leaf in child.leaves()):
                return child
        return container.children[-1]

    if op == "move":
        root = move(root, pane, direction, mru)
    elif op == "join":
        root = join(root, pane, direction)
    elif op == "flatten":
        root = flatten(root)
    root = tidy(root)
    assert root
    root.parent = None

    if min_len(root, "h") > sx or min_len(root, "v") > sy:
        tmux("display-message", "Not enough room to move this pane")
        return
    after = dump(root, 0, 0, sx, sy)
    if after == before:
        return

    # select-layout fills cells in pane-list order, so sort the list first.
    order = [leaf.pane for leaf in root.leaves()]
    panes = tmux("list-panes", "-t", pane_id, "-F", "#{pane_active} #{pane_id}").stdout.split()
    current = panes[1::2]
    active = next(p for flag, p in zip(panes[::2], current) if flag == "1")
    cmds = []
    for i, want in enumerate(order):
        if current[i] != want:
            j = current.index(want)
            # swap-pane -d leaves -s active, so the active pane goes there.
            a, b = (want, current[i]) if want == active else (current[i], want)
            cmds += ["swap-pane", "-d", "-s", a, "-t", b, ";"]
            current[i], current[j] = current[j], current[i]
    cmds += ["select-layout", "-t", pane_id, f"{checksum(after)},{after}"]
    result = tmux(*cmds)
    if result.returncode:
        tmux("display-message", f"tree.py: {result.stderr.strip()}")


if __name__ == "__main__":
    main()
