<?php

declare(strict_types=1);

namespace Drupal\Tests\todo_app\Functional;

use Drupal\Tests\BrowserTestBase;
use Drupal\node\Entity\Node;
use Drupal\node\Entity\NodeType;
use Drupal\field\Entity\FieldConfig;
use Drupal\field\Entity\FieldStorageConfig;
use Drupal\views\Entity\View;

/**
 * Functional tests for the todo_app module.
 *
 * @group todo_app
 */
class TodoAppTest extends BrowserTestBase {

  /**
   * {@inheritdoc}
   */
  protected $defaultTheme = 'stark';

  /**
   * {@inheritdoc}
   */
  protected static $modules = ['node', 'field', 'text', 'options', 'views', 'todo_app'];

  /**
   * The Todo content type machine name.
   */
  private const TODO_BUNDLE = 'todo';

  /**
   * Tests that the Todo content type is created on module install.
   */
  public function testTodoContentTypeExists(): void {
    $node_type = NodeType::load(self::TODO_BUNDLE);
    $this->assertNotNull($node_type, 'Todo content type should exist.');
    $this->assertSame('Todo', $node_type->label());
  }

  /**
   * Tests that the status (boolean) field exists on the Todo content type.
   */
  public function testTodoHasStatusField(): void {
    $storage = FieldStorageConfig::loadByName('node', 'field_status');
    $this->assertNotNull($storage, 'field_status storage should exist.');
    $this->assertSame('boolean', $storage->getType());

    $field = FieldConfig::loadByName('node', self::TODO_BUNDLE, 'field_status');
    $this->assertNotNull($field, 'field_status should be attached to todo bundle.');
  }

  /**
   * Tests that the description (text_long) field exists on the Todo content type.
   */
  public function testTodoHasDescriptionField(): void {
    $storage = FieldStorageConfig::loadByName('node', 'field_description');
    $this->assertNotNull($storage, 'field_description storage should exist.');
    $this->assertSame('text_long', $storage->getType());

    $field = FieldConfig::loadByName('node', self::TODO_BUNDLE, 'field_description');
    $this->assertNotNull($field, 'field_description should be attached to todo bundle.');
  }

  /**
   * Tests that a Todo node can be created and saved.
   */
  public function testCanCreateTodo(): void {
    $node = Node::create([
      'type' => self::TODO_BUNDLE,
      'title' => 'Buy milk',
      'field_description' => 'Get 1 liter of milk from the store.',
      'field_status' => 0,
    ]);
    $node->save();

    $loaded = Node::load($node->id());
    $this->assertNotNull($loaded);
    $this->assertSame('Buy milk', $loaded->getTitle());
    $this->assertSame('0', (string) $loaded->get('field_status')->value);
  }

  /**
   * Tests that a Todo can be marked done by updating the status field.
   */
  public function testCanMarkTodoDone(): void {
    $node = Node::create([
      'type' => self::TODO_BUNDLE,
      'title' => 'Write tests',
      'field_status' => 0,
    ]);
    $node->save();

    $node->set('field_status', 1);
    $node->save();

    $loaded = Node::load($node->id());
    $this->assertSame('1', (string) $loaded->get('field_status')->value);
  }

  /**
   * Tests that the /todos View exists and is reachable.
   */
  public function testTodosListViewExists(): void {
    $view = View::load('todos');
    $this->assertNotNull($view, 'View "todos" should exist.');

    $account = $this->drupalCreateUser(['access content']);
    $this->drupalLogin($account);
    $this->drupalGet('/todos');
    $this->assertSession()->statusCodeEquals(200);
  }

}
