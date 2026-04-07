# Implémentation du Generational Copying GC : Code et Pas à Pas

Pas de panique, c'est un sujet très complexe ! Voici un guide beaucoup plus détaillé avec **exactement le code Zig dont tu as besoin**.

On va procéder par petites étapes pour ne rien casser. 

---

## 💥 Étape 1 : Préparer `value.zig` au "Forwarding Pointer"

Quand l'objet est copié dans le nouveau bloc de mémoire, on doit laisser sa *"nouvelle adresse"* à l'ancien emplacement. C'est le Forwarding Pointer. 

Ouvre `rx/src/memory/value.zig`.

**1. Ajoute un Flag `MOVED` :**
A la ligne 21 (sous `FROZEN`), ajoute ceci :
```zig
pub const MOVED: u8 = 1 << 3; // L'objet a été déplacé par le GC
```

**2. Ajoute les méthodes utiles :**
```zig
    pub fn isMoved(self: *const HeapObject) bool {
        return (self.flags & MOVED) != 0;
    }
    pub fn markMoved(self: *HeapObject) void {
        self.flags |= MOVED;
    }
```

**3. L'astuce magique (Écrire par-dessus le payload) :**
Quand l'objet est copié, son `payload` (ex: les caractères de la string) ne sert plus à rien à l'ancienne adresse. On va utiliser cet espace vide pour stocker le pointeur vers la nouvelle adresse (sur 8 octets). Ajoute ces deux fonctions à la fin de la struct `HeapObject` :

```zig
    // Écrit le pointeur vers la nouvelle adresse au début du payload
    pub fn setForwardingPointer(self: *HeapObject, new_address: *HeapObject) void {
        // En Zig, on prend l'adresse juste après le header de l'objet
        const payload_ptr: *usize = @ptrFromInt(@intFromPtr(self) + @sizeOf(HeapObject));
        payload_ptr.* = @intFromPtr(new_address);
    }

    // Lit la nouvelle adresse (à n'utiliser QUE si isMoved() est true)
    pub fn getForwardingPointer(self: *const HeapObject) *HeapObject {
        std.debug.assert(self.isMoved());
        const payload_ptr: *const usize = @ptrFromInt(@intFromPtr(self) + @sizeOf(HeapObject));
        const addr: usize = payload_ptr.*;
        return @ptrFromInt(addr);
    }
```

*Félicitations, ton objet est prêt à informer la terre entière de son "déménagement" !*

---

## 💥 Étape 2 : Dédoubler la mémoire (`heap.zig`)

Actuellement, ton tas a un seul buffer. On va le couper en deux pour que les objets sautent de l'un à l'autre.

Ouvre `rx/src/memory/heap.zig`.

**1. Modifie la struct `Heap` :**
```zig
pub const Heap = struct {
    allocator: std.mem.Allocator,
    
    // NOUVEAU : Les 2 buffers
    from_space: []u8,
    to_space: []u8,
    
    offset: usize, // Offset dans le from_space
    capacity: usize, // La taille D'UN demi espace
    
    // ... tu peux garder ton array list 'strings' pour le moment
};
```

**2. Modifie `init()` pour allouer 2 espaces :**
```zig
    pub fn init(allocator: std.mem.Allocator, size: usize) !Heap {
        // On alloue 2 arrays !
        const from_buffer = try allocator.alignedAlloc(u8, .@"8", size);
        const to_buffer = try allocator.alignedAlloc(u8, .@"8", size);
        
        // ... garde l'init des strings
        
        return Heap{
            .allocator = allocator,
            .from_space = from_buffer,
            .to_space = to_buffer,
            .offset = 0,
            .capacity = size, // size est la taille pour UN buffer
            // ... autres champs 
        };
    }
```

**3. Modifie `deinit()` :**
```zig
    pub fn deinit(self: *Heap) void {
        // ...
        self.allocator.free(self.from_space);
        self.allocator.free(self.to_space);
    }
```

**4. Modifie l'allocation (`alloc`) pour vérifier l'espace !**
```zig
    pub fn alloc(self: *Heap, kind: HeapObject.Kind, payload_size: usize) !*HeapObject {
        const total_size = @sizeOf(HeapObject) + payload_size;
        const aligned_size = std.mem.alignForward(usize, total_size, 8);

        // NOUVEAU : Si c'est plein, ON VA CRASHER (Pour l'instant)
        // C'est normal, c'est le signal qu'il faut faire un GC !
        if (self.offset + aligned_size > self.capacity) {
            return error.OutOfMemory; // Ton CPU attrapera cette erreur pour déclencher collectGarbage()
        }

        // On écrit TOUJOURS dans le "from_space"
        const ptr_int = @intFromPtr(self.from_space.ptr) + self.offset;
        const obj: *HeapObject = @ptrFromInt(ptr_int);

        self.offset += aligned_size;
        
        // Setup de l'en-tête (inchangé)
        obj.* = HeapObject{
            .kind = kind,
            .flags = 0,
            .size = @intCast(payload_size),
        };
        
        return obj;
    }
```

*(Si tu lances ton code maintenant, il finira par faire un "Out Of Memory" car le buffer se remplit et n'est jamais vidé. C'est parfait.)*

---

## 💥 Étape 3 : Le Grand Nettoyage (Le Cheney's Copying)

Crée ce code (soit dans `heap.zig` soit dans `process.zig`) pour faire la copie. 
C'est la magie du GC !

**1. Comment copier UN objet (`copyObject`) :**

Cette fonction prend l'ancien pointeur et renvoie le nouveau.
```zig
    // Dans heap.zig, ajoute cette méthode :
    pub fn copyObject(self: *Heap, old_obj: *HeapObject) *HeapObject {
        // 1. Est-ce qu'il a déjà été copié par une autre variable ?
        if (old_obj.isMoved()) {
            return old_obj.getForwardingPointer();
        }

        // 2. Non, il est encore moisi dans le from_space ! On le copie.
        const total_size = @sizeOf(HeapObject) + old_obj.size;
        const aligned_size = std.mem.alignForward(usize, total_size, 8);

        // a. On trouve sa nouvelle place dans to_space (Note: on crée un NOUVEL offset appelé 'copy_offset' pendant le GC)
        const dest_ptr_int = @intFromPtr(self.to_space.ptr) + self.copy_offset;
        const new_obj: *HeapObject = @ptrFromInt(dest_ptr_int);

        // b. Copie bit-à-bit parfaite de TOUT l'objet et son payload (C'est ça le clônage !)
        const src_slice = @as([*]u8, @ptrCast(old_obj))[0..aligned_size];
        const dest_slice = @as([*]u8, @ptrCast(new_obj))[0..aligned_size];
        @memcpy(dest_slice, src_slice);

        // c. On avance le curseur (copy_offset)
        self.copy_offset += aligned_size;

        // d. L'ASTUCE : On va marquer le vieux corps (old_obj) comme "Déplacé" 
        // et on lui tatoue l'adresse de son nouvel avatar
        old_obj.markMoved();
        old_obj.setForwardingPointer(new_obj);

        return new_obj;
    }
```

**2. Comment mettre à jour une variable (`Value`) :**
Le GC ne doit mettre à jour que les valeurs qui sont des *Pointeurs*.

```zig
    // Toujours dans heap.zig
    pub fn copyValue(self: *Heap, val: *Value) void {
        if (!val.isPointer()) return; // On touche pas aux nombres et booléens
        
        const old_obj = val.asPointer() catch unreachable;
        
        // Vérifie si le pointeur appartient TRÈS SPECIFIQUEMENT à la mémoire de la machine et pas du C !
        // Dans une vraie VM, on vérifie adresse min/max du from_space.
        
        const new_obj = self.copyObject(old_obj);
        
        // On remplace le pointeur moisi de la variable par le tout beau tout neuf
        val.* = Value.pointer(new_obj);
    }
```

---

## 💥 Étape 4 : Le Cycle du GC (Dans le Processus)

C'est là où on orchestre tout : on trace, on scanne en largeur, et on échange.

Ouvre `process.zig` (ou là où tourne la VM) et écris ton premier Garbage Collector :

```zig
    // Dans Process
    pub fn collectGarbage(self: *Process) !void {
        const heap = &self.heap; // ou self.machine.heap
        
        // On recommence l'offset à zéro pour le Remplissage du to_space
        heap.copy_offset = 0; 
        heap.scanned_offset = 0; // Là où démarre le "scan en largeur" (Cheney)

        // PHASE 1 : Les Roots ! 
        // On demande au Heap de copier chaque variable qu'on "voit" directement 
        
        // 1. La Stack
        for (self.stack.items) |*val| {
            heap.copyValue(val);
        }
        
        // 2. Les CallFrames
        for (self.frames.items) |*frame| {
            // Le Closure est un pointeur HeapObject. Il faut un petit raccourci pour le mettre à jour.
            frame.closure = heap.copyObject(frame.closure);
        }

        // 3. La Mailbox
        for (self.mailbox.items) |*msg| {
            heap.copyValue(msg);
        }

        // PHASE 2 : Le Scan de Cheney (Récursivité à plat)
        // Les Roots sont maintenant dans to_space. 
        // Mais ils ("Closure", "Array") contiennent potentiellement des pointeurs vers le vieux from_space.
        
        // Tant qu'on n'a pas scanné tout ce qu'on a copié :
        while (heap.scanned_offset < heap.copy_offset) {
            const current_obj_ptr = @intFromPtr(heap.to_space.ptr) + heap.scanned_offset;
            const current_obj: *HeapObject = @ptrFromInt(current_obj_ptr);
            
            // Selon le type de l'objet, trouve ses enfants et copie-les !
            switch (current_obj.kind) {
                .string => {
                    // Les chaînes de caractères n'ont pas d'enfants (pas de pointeurs) ! Ouf !
                },
                .closure => {
                    // Trouver tous les upvalues (les Values stockées dans son payload)
                    // Et appeler heap.copyValue(&upvalue) sur CHACUN d'entre eux.
                    // ... TON CODE ICI ... (Utilise Closure.getEnvCount etc.)
                },
                .function => {
                    // Pareil, une fonction point-elle vers des strings ? des chunks ? 
                }
                // autres types...
            }
            
            // On a fini de scanner cet objet. On avance le curseur "scanned" à l'objet copié suivant.
            const total_size = @sizeOf(HeapObject) + current_obj.size;
            heap.scanned_offset += std.mem.alignForward(usize, total_size, 8);
        }
        
        // PHASE 3 : Le grand échange (Le Sweep magique gratuit !)
        // Tout ce qui est encore dans from_space est mort ! La mémoire est compactée dans to_space. 
        
        // On échange les pointeurs
        const temp = heap.from_space;
        heap.from_space = heap.to_space;
        heap.to_space = temp;
        
        // L'Offset d'allocation normal redevient 'copy_offset' (la taille des survivants !)
        heap.offset = heap.copy_offset;
    }
```

Prends ce plan et intègre-le petit à petit ! Si quelque chose ne compile pas ou paraît étrange point de vue architecture, n'hésite pas.
