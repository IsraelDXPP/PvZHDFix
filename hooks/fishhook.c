// Copyright (c) 2013, Facebook, Inc.
// All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//   * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//   * Neither the name Facebook nor the names of its contributors may be used to
//     endorse or promote products derived from this software without specific
//     prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING, NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "fishhook.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

#ifdef __LP64__
#if defined(__arm64__)
#define MH_MAGIC_HDR MH_MAGIC_64
#define MH_MAGIC_HDR_BE MH_CIGAM_64
#define LC_SEGMENT_ARCH LC_SEGMENT_64
#define LC_SEGMENT_ARCH_BE LC_SEGMENT_64
#else
#define MH_MAGIC_HDR MH_MAGIC_64
#define MH_MAGIC_HDR_BE MH_CIGAM_64
#define LC_SEGMENT_ARCH LC_SEGMENT_64
#define LC_SEGMENT_ARCH_BE LC_SEGMENT_64
#endif
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct nlist_64 nlist_t;
#else
#define MH_MAGIC_HDR MH_MAGIC
#define MH_MAGIC_HDR_BE MH_CIGAM
#define LC_SEGMENT_ARCH LC_SEGMENT
#define LC_SEGMENT_ARCH_BE LC_SEGMENT
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct nlist nlist_t;
#endif

struct rebindings_entry *rebindings_head;

static int prepend_rebindings(struct rebindings_entry **rebindings_head,
                              struct rebinding rebindings[],
                              size_t nel) {
  struct rebindings_entry *new_entry = (struct rebindings_entry *)malloc(sizeof(struct rebindings_entry));
  if (!new_entry) {
    return -1;
  }
  new_entry->rebindings = (struct rebinding *)malloc(sizeof(struct rebinding) * nel);
  if (!new_entry->rebindings) {
    free(new_entry);
    return -1;
  }
  memcpy(new_entry->rebindings, rebindings, sizeof(struct rebinding) * nel);
  new_entry->rebindings_nel = nel;
  new_entry->next = *rebindings_head;
  *rebindings_head = new_entry;
  return 0;
}

struct binding_info {
  uintptr_t address;
  uint8_t type;
};

struct section_binding_info {
  const struct section_binding_info *next;
  const struct mach_header_t *header;
  intptr_t slide;
  struct binding_info *bindings;
  size_t bindings_count;
  const char *segment_name;
  const char *section_name;
};

static int perform_rebinding_with_section(
    struct rebindings_entry *rebindings,
    struct section_binding_info *section_info,
    intptr_t slide,
    nlist_t *symtab,
    char *strtab,
    uint32_t *indirect_symtab
) {
  const uint32_t *indirect_symbol_indices = indirect_symtab;
  uint32_t *indirect_symbol_bindings = (uint32_t *)section_info->bindings;
  
  for (uint32_t i = 0; i < section_info->bindings_count; i++) {
    uint32_t symtab_index = indirect_symbol_indices[i];
    if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
        symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
      continue;
    }
    
    uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
    char *symbol_name = strtab + strtab_offset;
    
    if (symbol_name[0] == '_') {
      symbol_name++;
    }
    
    struct rebindings_entry *cur = rebindings;
    while (cur) {
      for (size_t j = 0; j < cur->rebindings_nel; j++) {
        if (strcmp(&symbol_name[1], cur->rebindings[j].name) == 0 ||
            strcmp(symbol_name, cur->rebindings[j].name) == 0) {
          if (cur->rebindings[j].replaced != NULL &&
              indirect_symbol_bindings[i] != (uintptr_t)cur->rebindings[j].replacement) {
            *(cur->rebindings[j].replaced) = (void *)indirect_symbol_bindings[i];
          }
          indirect_symbol_bindings[i] = (uintptr_t)cur->rebindings[j].replacement;
          goto symbol_loop;
        }
      }
      cur = cur->next;
    }
  symbol_loop:;
  }
  return 0;
}

static void rebind_symbols_for_image(struct rebindings_entry *rebindings,
                                     const struct mach_header_t *header,
                                     intptr_t slide) {
  // ... (simplified for brevity - full implementation available on GitHub)
  // For the actual fishhook implementation, please use the official source:
  // https://github.com/facebook/fishhook/blob/main/fishhook.c
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
  int retval = prepend_rebindings(&rebindings_head, rebindings, rebindings_nel);
  if (retval < 0) {
    return retval;
  }
  
  // If we've already rebinded, we need to rebind again
  // For each image, apply the new rebindings
  if (rebindings_head->next != NULL) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
      rebind_symbols_for_image(
          rebindings_head,
          (const struct mach_header_t *)_dyld_get_image_header(i),
          _dyld_get_image_vmaddr_slide(i)
      );
    }
  }
  
  return 0;
}

int rebind_symbols_image(void *header,
                         intptr_t slide,
                         struct rebinding rebindings[],
                         size_t rebindings_nel) {
  struct rebindings_entry *rebindings_head_local = NULL;
  int retval = prepend_rebindings(&rebindings_head_local, rebindings, rebindings_nel);
  if (retval < 0) {
    return retval;
  }
  rebind_symbols_for_image(rebindings_head_local, (const struct mach_header_t *)header, slide);
  free(rebindings_head_local->rebindings);
  free(rebindings_head_local);
  return retval;
}
