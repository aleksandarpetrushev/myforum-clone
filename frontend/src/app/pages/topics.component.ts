import { Component, inject, signal } from '@angular/core';
import { ForumApi } from '../core/forum-api';
import { Topic } from '../core/models';

@Component({
  selector: 'app-topics',
  templateUrl: './topics.component.html',
})
export class TopicsComponent {
  private readonly api = inject(ForumApi);
  readonly topics = signal<Topic[]>([]);
  readonly error = signal<string | null>(null);

  constructor() {
    this.load();
  }

  load(): void {
    this.api.topics().subscribe({
      next: (response) => this.topics.set(response.data),
      error: () => this.error.set('Could not load topics'),
    });
  }

  toggle(topic: Topic): void {
    const request = topic.followed ? this.api.unfollow(topic.id) : this.api.follow(topic.id);
    request.subscribe({
      next: () => this.load(),
      error: () => this.error.set('Could not update that topic'),
    });
  }
}
