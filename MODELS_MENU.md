# Dio Node Library & Settings Design Overview

## Overview

The Node Library and Node Settings are key UI components for Dio, a mobile-first node editor for creative AI workflows. These mockups showcase a **task-first node organization system** and a **model-aware settings interface** designed for clarity, scalability, and touch-native use.

---

## 1. Node Library (Task-First Design)

### Purpose

Help creators quickly find and insert functional nodes (actions like Image Gen, Video Gen, Upscale, etc.) without being overwhelmed by model-level complexity.

### Structure

The Node Library appears as a **bottom sheet** over the canvas, optimized for mobile ergonomics. It consists of:

* **Search Bar:** Universal search by *task*, *model*, or *style keyword* (e.g., “upscale”, “veo”, “anime”).
* **Filter Chips:** Horizontal scrollable filters for major categories: All, Image, Video, Edit, Utility, Recent, Popular.
* **Category Sections:** Collapsible sections grouping nodes by their *output type* or *creative goal* (e.g., Image Generation, Video Generation, Editing).

Each section displays a **grid of node cards**, with:

* **Icon + Name** (e.g., 🖼️ *Text → Image*).
* **Short Description** for task clarity.
* **Outputs Label** (e.g., “Outputs: Image”) to guide valid graph connections.
* **Add Button** for quick insertion.

### Interaction Flow

1. Tap “+ Add Node” → bottom sheet slides up.
2. Browse or search for the desired task.
3. Tap “＋ Add” to insert the node into the canvas.

### UX Principles

* **Task-oriented over model-oriented:** Users think in terms of outcomes, not model names.
* **Low cognitive load:** Grouping by output type reduces scrolling and decision fatigue.
* **Search-first fallback:** Power users can type known model names directly.
* **Progressive reveal:** Model selection happens *after* the node is added.

---

## 2. Node Settings (Model-Aware Design)

### Purpose

Allow users to fine-tune a node’s behavior—such as prompts, parameters, and model choice—without cluttering the mobile UI.

### Structure

Displayed as a **full-screen panel** when a node is selected. The layout includes:

* **Top Bar:** Node name, context (e.g., “Image Gen – Node Settings”), and quick actions (Duplicate, Bypass, Connect).
* **Model Group:** Abstracted default model with a secondary dropdown to change or browse FAL models.
* **Prompt Group:** Text prompt input with placeholder examples.
* **Controls Group:** Relevant parameters (output size, guidance/CFG, seed). Advanced settings are collapsible.
* **Run Bar:** Progress indicator + Run button at the bottom.

### Model Abstraction Strategy

* Default to **“Recommended” profiles** per node type (e.g., Balanced Image Model).
* Offer a **“Browse all FAL models”** fallback for experts.

### UX Principles

* **Abstract first, reveal second:** Beginners use recommended defaults; experts can switch models.
* **Contextual settings:** Only show controls relevant to the selected node type.
* **Consistent feedback:** Always display progress, even for remote tasks.

---

## 3. Visual Language

* **Color palette:** Dark UI with cool accents (blue-teal gradients) to evoke creative and tech-forward feel.
* **Rounded corners and haptics:** Touch-friendly design emphasizing comfort.
* **Consistent badges:** “Outputs: Image/Video” badges visually reinforce data flow types.

---

## 4. Design Goals

1. **Discoverability:** Simplify finding the right node among many FAL models.
2. **Scalability:** Support new model categories without redesign.
3. **Mobile ergonomics:** Keep actions within thumb reach and use one-tap additions.
4. **Creativity through clarity:** Make workflows understandable, not magical.

---

## Summary

Dio’s node menu system balances *accessibility* and *power*. By organizing nodes around creative tasks (not models) and abstracting model complexity behind clear UI layers, it empowers creators to explore AI workflows intuitively—even on a phone.
